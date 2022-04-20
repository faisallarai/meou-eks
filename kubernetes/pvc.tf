resource "aws_security_group" "sg_efs" {
  description = "Security Group to allow NFS"
  name = "efs-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    cidr_blocks = [ var.vpc_cidr ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "efs" {
  creation_token = "efs-token"

  tags = {
    Name = "kubernetes-pv"
  }
}

resource "aws_efs_mount_target" "mount_target" {
  count = length(var.efs_subnet_ids)

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = element(var.efs_subnet_ids[*], count.index)
  security_groups = [ aws_security_group.sg_efs.id ]
}

resource "aws_iam_policy" "efs_csi_iam_policy" {
  name   = "AmazonEKS_EFS_CSI_Driver_Policy"
  path   = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "elasticfilesystem:CreateAccessPoint"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow",
        Action = "elasticfilesystem:DeleteAccessPoint",
        Resource = "*",
        Condition = {
          StringEquals: {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "efs_csi_iam_role" {
  name        = "AmazonEKS_EFS_CSI_DriverRole"
  description = "Permissions required by the Kubernetes AWS EFS CSI Driver to do its job."

  force_detach_policies = true

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.eks_oidc_url, "https://", "")}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_url, "https://", "")}:sub": "system:serviceaccount:${var.kubernetes_namespace}:efs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_role_policy_attachment" {
  policy_arn = aws_iam_policy.efs_csi_iam_policy.arn
  role       = aws_iam_role.efs_csi_iam_role.name
}

resource "kubernetes_storage_class_v1" "efs_sc" {
  metadata {
    name = "efs-sc"
  }
  storage_provisioner = "efs.csi.aws.com"
  parameters = {
    type = "pd-standard"
    provisioning_mode = "efs-ap"
    file_system_id = aws_efs_file_system.efs.id
    directory_perms = "700"
  }
}

resource "kubernetes_service_account" "efs_csi_controller_sa" {
  metadata {
    name = "efs-csi-controller-sa"
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name" = "aws-efs-csi-driver"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.efs_csi_iam_role.arn
    }
  }
}

resource "kubernetes_cluster_role" "efs_csi_external_provisioner_role" {
  metadata {
    name = "efs-csi-external-provisioner-role"

    labels = {
      "app.kubernetes.io/name" = "aws-efs-csi-driver"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes"]
    verbs      = ["create", "get", "list", "watch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "update"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["list", "watch", "create"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["csinodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "delete", "update", "create"]
  }
}

resource "kubernetes_cluster_role_binding" "efs_csi_provisioner_binding" {
  metadata {
    name = " efs-csi-provisioner-binding"

    labels = {
      "app.kubernetes.io/name"       = "aws-efs-csi-driver"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.efs_csi_external_provisioner_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.efs_csi_controller_sa.metadata[0].name
    namespace = var.kubernetes_namespace
  }
}



resource "kubernetes_deployment" "efs_csi_controller" {
  metadata {
    name = "efs-csi-controller"
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name" = "aws-efs-csi-driver"
    }
  }

  spec {
    replicas = var.efs_replicas

    selector {
      match_labels = {
        app = "efs-csi-controller"
        "app.kubernetes.io/instance" = "kustomize"
        "app.kubernetes.io/name" = "aws-efs-csi-driver"
      }
    }

    template {
      metadata {
        labels = {
          app = "efs-csi-controller"
          "app.kubernetes.io/instance" = "kustomize"
          "app.kubernetes.io/name" = "aws-efs-csi-driver"
        }
      }

      spec {
        container {
          args = ["--endpoint=$(CSI_ENDPOINT)",
            "--logtostderr",
            "--v=2",
            "--delete-access-point-root-dir=false"]
          
          env {
            name = "CSI_ENDPOINT"
            value = "unix:///var/lib/csi/sockets/pluginproxy/csi.sock"
          }

          image = "602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-efs-csi-driver:v1.2.1"
          image_pull_policy = "IfNotPresent"

          liveness_probe {

            http_get {
              path = "/healthz"
              port = "healthz"

              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
            }

            initial_delay_seconds = 10
            period_seconds        = 10

            failure_threshold = 5
            timeout_seconds = 3
          }

          name =  "efs-plugin"

          port {
              container_port = "9909"
              name = "healthz"
              protocol = "TCP"
          }

          security_context {
            privileged = true
          }

          volume_mount {
            mount_path = "/var/lib/csi/sockets/pluginproxy/"
            name = "socket-dir"
          }

        }

        container {

          args = [
            "--csi-address=$(ADDRESS)",
            "--v=2",
            "--feature-gates=Topology=true",
            "--leader-election"
          ]

          env {
            name = "ADDRESS"
            value = "/var/lib/csi/sockets/pluginproxy/csi.sock"
          }

          name = "csi-provisioner"
          image = "public.ecr.aws/eks-distro/kubernetes-csi/external-provisioner:v2.1.1-eks-1-18-2"

          volume_mount {
            mount_path = "/var/lib/csi/sockets/pluginproxy/"
            name = "socket-dir"
          }
        }

        container {
          
          args = [
            "--csi-address=/csi/csi.sock",
            "--health-port=9909"
          ]
          
          image = "public.ecr.aws/eks-distro/kubernetes-csi/livenessprobe:v2.2.0-eks-1-18-2"
          name = "liveness-probe"

          volume_mount {
            mount_path = "/csi"
            name =  "socket-dir"
          }
        }
        
        host_network = true
        node_selector = {
          "kubernetes.io/os" = "linux"
        }
          
        priority_class_name = "system-cluster-critical"
        service_account_name = "efs-csi-controller-sa"
        toleration {
          operator = "Exists"
        }
       
        volume {
          empty_dir {}
          name = "socket-dir"
        }

      }
    }
  }
}

resource "kubernetes_daemonset" "efs_csi_node" {
  metadata {
    name = "efs-csi-node"
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name" = "aws-efs-csi-driver"
    }
  }

  spec {

    selector {
      match_labels = {
        app = "efs-csi-node"
        "app.kubernetes.io/instance" = "kustomize"
        "app.kubernetes.io/name" = "aws-efs-csi-driver"
      }
    }

    template {
      metadata {
        labels = {
          app = "efs-csi-node"
          "app.kubernetes.io/instance" = "kustomize"
          "app.kubernetes.io/name" = "aws-efs-csi-driver"
        }
      }

      spec {
        affinity{
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key = "eks.amazonaws.com/compute-type"
                  operator = "NotIn"
                  values = ["fargate"]
                }
              }
            }
          }
        }
         
        container {
          args = [
            "--endpoint=$(CSI_ENDPOINT)",
            "--logtostderr",
            "--v=2",
          ]

          env {
            name = "CSI_ENDPOINT"
            value = "unix:/csi/csi.sock"
          }
            
          image = "602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-efs-csi-driver:v1.2.1"
          
          liveness_probe {
            failure_threshold = 5

            http_get {
              path = "/healthz"
              port = "healthz"
            }

            initial_delay_seconds = 10
            period_seconds = 2
            timeout_seconds = 3
          }
            
          name = "efs-plugin"

          port {
            container_port = 9809
            name = "healthz"
            protocol = "TCP"
          }
        
          security_context {
            privileged = true
          }
            
          volume_mount {
            mount_path = "/var/lib/kubelet"
            mount_propagation = "Bidirectional"
            name = "kubelet-dir"
          }

          volume_mount {
            mount_path = "/csi"
            name = "plugin-dir"
          }

          volume_mount {
            mount_path = "/var/run/efs"
            name = "efs-state-dir"
          }

          volume_mount {
            mount_path = "/var/amazon/efs"
            name = "efs-utils-config"
          }

          volume_mount {
            mount_path = "/etc/amazon/efs-legacy"
            name = "efs-utils-config-legacy"
          }
           
        }

        container {
           
          args = [
            "--csi-address=$(ADDRESS)",
            "--kubelet-registration-path=$(DRIVER_REG_SOCK_PATH)",
            "--v=2"
          ]
            
          env {
            name = "ADDRESS"
            value = "/csi/csi.sock"
          }

          env {
            name = "DRIVER_REG_SOCK_PATH"
            value = "/var/lib/kubelet/plugins/efs.csi.aws.com/csi.sock"
          }

          env {
            name = "KUBE_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            } 
          }
           
          image = "public.ecr.aws/eks-distro/kubernetes-csi/node-driver-registrar:v2.1.0-eks-1-18-2"
          name = "csi-driver-registrar"

          volume_mount {
            mount_path = "/csi"
            name = "plugin-dir"
          }

          volume_mount {
            mount_path = "/registration"
            name = "registration-dir"
          }
        
        }

        container {

          args = [
            "--csi-address=/csi/csi.sock",
            "--health-port=9809",
            "--v=2"
          ]
            
          image = "public.ecr.aws/eks-distro/kubernetes-csi/livenessprobe:v2.2.0-eks-1-18-2"
          name = "liveness-probe"

          volume_mount {
            mount_path = "/csi"
            name = "plugin-dir"
          }

        }
        
        host_network = true
        node_selector  = {
          "beta.kubernetes.io/os" = "linux"
        }
          
        priority_class_name = "system-node-critical"
        toleration {
          operator = "Exists"
        }

        volume {
          host_path {
            path = "/var/lib/kubelet"
            type = "Directory"
          }
          name = "kubelet-dir"
        }

        volume {
          host_path {
            path = "/var/lib/kubelet/plugins/efs.csi.aws.com/"
            type = "DirectoryOrCreate"
          }
          name = "plugin-dir"
        }

        volume {
          host_path {
            path = "/var/lib/kubelet/plugins_registry/"
            type = "Directory"
          }
          name = "registration-dir"
        }

        volume {
          host_path {
            path = "/var/run/efs"
            type = "DirectoryOrCreate"
          }
          name = "efs-state-dir"
        }

        volume {
          host_path {
            path = "/var/amazon/efs"
            type = "DirectoryOrCreate"
          }
          name = "efs-utils-config"
        }

        volume {
          host_path {
            path = "/etc/amazon/efs"
            type = "DirectoryOrCreate"
          }
          name = "efs-utils-config-legacy"
        }

      }
    }
  }
}

resource "kubernetes_csi_driver_v1" "efs_csi_aws_com" {
  metadata {
    annotations = {
      "helm.sh/hook" = "pre-install, pre-upgrade"
      "helm.sh/hook-delete-policy" = "before-hook-creation"
      "helm.sh/resource-polic" = "keep"
    }
    name = "efs.csi.aws.com"
  }

  spec {
    attach_required        = false
  }
}

resource "kubernetes_persistent_volume_v1" "efs_pv_0" {
  metadata {
    name = "efs-pv-0"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    volume_mode = "Filesystem"
    access_modes = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "efs-sc"
    persistent_volume_source {
      csi {
        driver = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.efs.id
      }
    }
  }
  # depends_on = [ kubernetes_storage_class.efs_sc ]
}

resource "kubernetes_persistent_volume_v1" "efs_pv_1" {
  metadata {
    name = "efs-pv-1"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    volume_mode = "Filesystem"
    access_modes = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "efs-sc"
    persistent_volume_source {
      csi {
        driver = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.efs.id
      }
    }
  }
  # depends_on = [ kubernetes_storage_class.efs_sc ]
}

resource "kubernetes_persistent_volume_v1" "efs_pv_2" {
  metadata {
    name = "efs-pv-2"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    volume_mode = "Filesystem"
    access_modes = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "efs-sc"
    persistent_volume_source {
      csi {
        driver = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.efs.id
      }
    }
  }
  # depends_on = [ kubernetes_storage_class.efs_sc ]
}

resource "kubernetes_persistent_volume_v1" "efs_pv_3" {
  metadata {
    name = "efs-pv-3"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    volume_mode = "Filesystem"
    access_modes = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "efs-sc"
    persistent_volume_source {
      csi {
        driver = "efs.csi.aws.com"
        volume_handle = aws_efs_file_system.efs.id
      }
    }
  }
  # depends_on = [ kubernetes_storage_class.efs_sc ]
}