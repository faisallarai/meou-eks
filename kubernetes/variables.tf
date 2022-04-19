variable "region" {
    type = string
    description = "AWS Region"
}

variable "vpc_id" {
    type = string
    description = "EKS Cluster VPC ID"
}

variable "vpc_cidr" {
    type = string
    description = "VPC CIDR Block"
}

variable "efs_subnet_ids" {
    type = list(string)
    description = "Subnets ID's for EFS Mount Targets"
}

variable "eks_cluster_name" {
    description = "Name of the EKS Cluster"
}

variable "eks_cluster_id" {
    description = "ID of the EKS Cluster"
}

variable "eks_cluster_endpoint" {
    type = string
    description = "EKS Cluster Endpoint"
}

variable "eks_oidc_url" {
    type = string
    description = "EKS Cluster OIDC Provider URL"
}

variable "eks_ca_certificate" {
    type = string
    description = "EKS Cluster CA Certificate"
}

variable "kubernetes_namespace" {
    type = string
    description = "Name of the Kubernetes Namespace"
}

variable "app_namespace" {
    type = string
    description = "Name of the App Namespace"
}

variable "app_labels" {
    type = map
    description = "List of the labels for Apps Deployment"
}

variable "namespace_depends_on" {
  type    = any
  default = null
}

variable "efs_replicas" {
    type = string
    description = "Number of replicas for the Deployment"
}