resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.app_namespace
    labels = var.app_labels
  }
}

