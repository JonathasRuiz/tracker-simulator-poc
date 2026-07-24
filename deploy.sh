#!/bin/bash
# deploy.sh

echo "=========================================="
echo "🚀 Welcome to the MyApp Automated Installer"
echo "=========================================="

# NEW: Check if user configured their values
read -p "Did you update the tracker-simulator.values.yaml and 'tracker-simulator-envoy.values.yaml' file with your settings? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please update custom-values.yaml and run this script again."
    exit 1
fi

# 1. Prerequisites Check
if ! command -v terraform &> /dev/null; then echo "Error: Terraform not installed."; exit 1; fi
if ! command -v kubectl &> /dev/null; then echo "Error: kubectl not installed (required to fetch LB IP)."; exit 1; fi

# 2. Load credentials from .env
if [ ! -f ".env" ]; then
    echo "Error: .env file not found. Please create one with DO_TOKEN and GOOGLE_API_KEY."
    exit 1
fi
set -a
source .env
set +a

if [ -z "$DO_TOKEN" ]; then
    echo "Error: DO_TOKEN is not set in .env."
    exit 1
fi
if [ -z "$GOOGLE_API_KEY" ]; then
    echo "Error: GOOGLE_API_KEY is not set in .env."
    exit 1
fi

export TF_VAR_do_token=$DO_TOKEN
export TF_VAR_google_api_key=$GOOGLE_API_KEY

# 4. Prompt for the SSH public key
read -p "Enter path to your SSH public key [~/.ssh/id_rsa.pub]: " SSH_KEY_PATH
SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa.pub}
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH public key not found at '$SSH_KEY_PATH'."
    exit 1
fi
export TF_VAR_ssh_public_key=$(cat "$SSH_KEY_PATH")

# 5. Execute Terraform
echo ""
echo "Initializing Terraform..."
terraform init -input=false

# Import SSH key if it already exists in DigitalOcean to avoid "already in use" error
SSH_FINGERPRINT=$(ssh-keygen -l -E md5 -f "$SSH_KEY_PATH" 2>/dev/null | awk '{print $2}' | sed 's/^MD5://')
if [ -n "$SSH_FINGERPRINT" ]; then
    EXISTING_KEY_ID=$(curl -s -H "Authorization: Bearer $DO_TOKEN" \
        "https://api.digitalocean.com/v2/account/keys" | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
fp = '${SSH_FINGERPRINT}'
for key in data.get('ssh_keys', []):
    if key.get('fingerprint') == fp:
        print(key['id'])
        break
" 2>/dev/null)
    if [ -n "$EXISTING_KEY_ID" ]; then
        echo "SSH key already exists in DigitalOcean (ID: $EXISTING_KEY_ID), importing into Terraform state..."
        terraform import digitalocean_ssh_key.default "$EXISTING_KEY_ID" 2>/dev/null || true
    fi
fi

terraform apply -auto-approve

# 5. Extract Kubeconfig
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml


# 6. Wait for the Load Balancer IP
echo ""
echo "⏳ Phase 2: Waiting for DigitalOcean to assign a Load Balancer IP..."
echo "(This usually takes 2-3 minutes)"

# Based on your EnvoyProxy config, Gateway API usually names the service roughly like this.
# You may need to verify the exact service name Envoy Gateway generates in your namespace.
ENVOY_SVC_NAME=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=default -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

REAL_IP=""
while [ -z "$REAL_IP" ]; do
    sleep 10
    echo "Still waiting for IP..."
    REAL_IP=$(kubectl get svc $ENVOY_SVC_NAME -n envoy-gateway-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
done

echo "✅ Load Balancer IP acquired: $REAL_IP"

# 7. Phase 3: Final configuration injection
echo ""
echo "⚙️  Phase 3: Injecting IP into application configuration..."
# We run Terraform again, but this time we pass the real IP!
export TF_VAR_load_balancer_ip=$REAL_IP
terraform apply -auto-approve

echo ""
echo "🎉 DEPLOYMENT COMPLETE! 🎉"
echo "Your application is live at: $REAL_IP"