resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.app_namespace
    labels = var.app_labels
  }
}

resource "kubernetes_namespace" "argo_cd" {
  metadata {
    name = "argocd"
    labels = {
      "name" = "arogcd"
    }
  }
}

