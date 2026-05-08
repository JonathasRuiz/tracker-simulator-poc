resource "digitalocean_ssh_key" "default" {
  name       = "myapp-deploy-key"
  public_key = var.ssh_public_key
}

# Size slug format: <plan>-<vcpu>vcpu-<ram>
#   s-* = Basic (shared CPU) — cheapest
#   g-* = General Purpose
#   c-* = CPU-Optimized
resource "digitalocean_droplet" "compose_server" {
  image      = "ubuntu-24-04-x64"
  name       = "myapp-compose-node"
  region     = var.region
  size       = "s-2vcpu-4gb"
  ssh_keys   = [digitalocean_ssh_key.default.fingerprint]
  user_data  = file("${path.module}/cloud-init.yaml")
}

output "droplet_ip" {
  value = digitalocean_droplet.compose_server.ipv4_address
}