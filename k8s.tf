resource "digitalocean_kubernetes_cluster" "app_cluster" {
  name    = "myapp-k8s-cluster"
  region  = var.region
  version = "1.35.1-do.5" # Use a current version from doctl kubernetes options
  ha      = false          # Disable HA control plane — saves ~$40/mo, fine for a PoC

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-4gb"
    node_count = var.node_count
  }
}

output "kubernetes_cluster_id" {
  value = digitalocean_kubernetes_cluster.app_cluster.id
}

output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.app_cluster.kube_config[0].raw_config
  sensitive = true
}