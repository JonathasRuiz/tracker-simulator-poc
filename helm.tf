# 1. Install Gateway API CRDs & Envoy Gateway Controller
resource "helm_release" "envoy_gateway" {
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.2.0" # Matches the v1.2.0 in your README
  namespace        = "envoy-gateway-system"
  create_namespace = true

  # This tells the chart to also install the standard Gateway API CRDs
  set {
    name  = "installGatewayAPI"
    value = "true"
  }

  depends_on = [digitalocean_kubernetes_cluster.app_cluster]
}

# 2. Install the Applications chart.
resource "helm_release" "tracker_simulator" {
  name       = "tracker-simulator"  
  chart      = "https://github.com/JonathasRuiz/tracker-simulator-chart/raw/refs/heads/master/tracker-simulator-0.1.0.tgz"
  namespace        = "default"
  create_namespace = true

  # Inject the user's filled-out values file
  values = [
    templatefile("${path.module}/tracker-simulator.values.yaml", {
        # Pass the dynamically generated Droplet IP into the YAML
        droplet_ip = digitalocean_droplet.compose_server.ipv4_address
        load_balancer_ip = var.load_balancer_ip
        google_api_key = google_api_key
        })    
  ]

  # CRITICAL: Tell Terraform it MUST wait for the cluster to exist first
  depends_on = [digitalocean_kubernetes_cluster.app_cluster]
}

# 2. Deploy Envoy Ingress service
resource "helm_release" "tracker_simulator_envoy" {
  name             = "tracker-simulator-envoy"  
  chart            = "https://github.com/JonathasRuiz/tracker-simulator-envoy-chart/raw/refs/heads/master/tracker-simulator-envoy-0.1.0.tgz"
  namespace        = "envoy-gateway-system"
  create_namespace = true

values = [
    templatefile("${path.module}/tracker-simulator-envoy.values.yaml", {})
  ]  

  depends_on = [
        digitalocean_kubernetes_cluster.app_cluster,
        helm_release.envoy_gateway,
        helm_release.tracker_simulator
    ]
}