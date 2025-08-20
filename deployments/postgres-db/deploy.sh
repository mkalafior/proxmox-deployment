#!/bin/bash

# Service-specific deployment script
set -euo pipefail

# Get script directory and service name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "🚀 Deploying $SERVICE_NAME"
echo "=========================="

# Check if we're in the right directory
if [[ ! -f "deploy.yml" ]]; then
    log_error "Please run this script from the service deployment directory"
    exit 1
fi

# Load clean environment (prevents variable pollution)
source ../../global-config/load-env.sh
if ! load_clean_env "postgres-db" "$(pwd)"; then
    log_error "Failed to load clean environment"
    exit 1
fi
if [[ -f "../../global-config/env.proxmox.global" ]]; then
else


# Check required environment variables
if [[ -z "${PROXMOX_HOST:-}" ]]; then
    log_error "PROXMOX_HOST not configured in global settings"
    exit 1
fi

# Install required Ansible collections
log_step "Installing Ansible requirements..."
ansible-galaxy collection install community.general --force >/dev/null 2>&1

# Validate playbook
log_step "Validating deployment configuration..."
ansible-playbook deploy.yml --syntax-check >/dev/null

# Show deployment plan
echo ""
echo "🎯 Deployment Plan for $SERVICE_NAME:"
echo "   Proxmox Host: ${PROXMOX_HOST}"
echo "   VM ID: ${VM_ID}"
echo "   Application Port: ${APP_PORT}"
echo "   Service Hostname: ${SERVICE_HOSTNAME:-$SERVICE_NAME}"
if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
    echo "   Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
fi
echo ""

# Run deployment
log_info "Starting deployment of $SERVICE_NAME..."
if ansible-playbook deploy.yml -v; then
    log_info "✅ $SERVICE_NAME deployment completed successfully"
    
    # Show access information
    if [[ -f "vm_ip.txt" ]]; then
        VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')
        echo ""
        echo "🎉 $SERVICE_NAME is now running!"
        echo "   Local URL: http://${VM_IP}:${APP_PORT}"
        echo "   Health Check: http://${VM_IP}:${APP_PORT}/health"
        if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
            echo "   Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
        fi
        echo ""
        echo "🔧 Management:"
        echo "   Status: ./manage.sh status"
        echo "   Logs: ./manage.sh logs"
        echo "   SSH: ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    fi
else
    log_error "$SERVICE_NAME deployment failed"
    exit 1
fi
