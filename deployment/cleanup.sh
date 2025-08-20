#!/bin/bash

# Simplified Cleanup Script for Hello World Bun App
# Usage: ./cleanup.sh

set -euo pipefail

# Configuration
TUNNEL_NAME="${TUNNEL_NAME:-proxmox-main}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-app}"
SSH_KEY_PATH="$HOME/.ssh/id_proxmox"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🧹 Hello World Bun App - Cleanup Deployment"
echo "============================================"

# Check if we're in the right directory
if [[ ! -f "deploy.yml" ]]; then
    log_error "Please run this script from the deployment directory"
    echo "   cd deployment && ./cleanup.sh"
    exit 1
fi

# Load environment variables
if [[ -f "../env.proxmox" ]]; then
    source ../env.proxmox
    log_info "Loaded environment from env.proxmox"
else
    log_error "env.proxmox file not found"
    exit 1
fi

# Check required environment variables
if [[ -z "${PROXMOX_HOST:-}" ]]; then
    log_error "PROXMOX_HOST environment variable is not set"
    exit 1
fi

# Check authentication
if [[ -z "${PROXMOX_PASSWORD:-}" && ( -z "${TOKEN_ID:-}" || -z "${TOKEN_SECRET:-}" ) ]]; then
    log_error "No Proxmox authentication configured"
    exit 1
fi

# Check if ansible is installed
if ! command -v ansible &> /dev/null; then
    log_error "Ansible is not installed"
    exit 1
fi

# Show what will be cleaned up
echo ""
echo "🗑️  This will remove the following resources:"
echo "   • Proxmox Container: hello-world-bun-app (VM ID: ${VM_ID:-200})"
echo "   • All application data and logs"
echo "   • DNS records for service hostname"
echo "   • Local deployment files (vm_ip.txt)"
if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
    echo "   • Cloudflare tunnel route: ${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
fi
echo ""

# Get VM IP if available
VM_IP=""
if [[ -f "vm_ip.txt" ]]; then
    VM_IP=$(cat vm_ip.txt)
    echo "   • Target VM IP: $VM_IP"
fi

# Show hostname that will be cleaned up
SERVICE_HOSTNAME="${SERVICE_HOSTNAME:-hello-world-bun-app}"
echo "   • DNS hostname: ${SERVICE_HOSTNAME}.proxmox.local"

echo ""
echo "⚠️  WARNING: This action cannot be undone!"
echo ""

# Confirm cleanup
read -p "🤔 Are you sure you want to delete the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

echo ""
echo "🗑️  Starting cleanup..."

# Stop the container first (if it exists and is accessible)
if [[ -n "$VM_IP" ]] && [[ -f "$HOME/.ssh/id_proxmox" ]]; then
    echo "   Stopping application service..."
    ansible all -i "${VM_IP}," -u root --private-key="$HOME/.ssh/id_proxmox" \
        -m systemd -a "name=hello-world-bun-app state=stopped" \
        --ssh-extra-args="-o ConnectTimeout=10 -o StrictHostKeyChecking=no" \
        2>/dev/null || echo "   (Service stop failed or VM not accessible)"
    
    # Clean up DNS records
    echo "   Cleaning up DNS records..."
    SERVICE_HOSTNAME="${SERVICE_HOSTNAME:-hello-world-bun-app}"
    ansible all -i "${VM_IP}," -u root --private-key="$HOME/.ssh/id_proxmox" \
        -m shell -a "/opt/dns-register.sh cleanup" \
        --ssh-extra-args="-o ConnectTimeout=10 -o StrictHostKeyChecking=no" \
        2>/dev/null && echo "   ✅ DNS records cleaned up" || echo "   (DNS cleanup failed or not configured)"
fi

# Clean up Cloudflare tunnel routing (if configured)
if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
    echo "   Removing Cloudflare tunnel route..."
    if ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes root@${PROXMOX_HOST} \
        "cloudflared tunnel route dns --overwrite-dns ${TUNNEL_NAME} ${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}" 2>/dev/null; then
        echo "   ✅ Removed Cloudflare DNS route"
    else
        echo "   (Could not remove Cloudflare route - may not exist or SSH failed)"
    fi
    
    # Update tunnel config to remove app routing
    if ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes root@${PROXMOX_HOST} \
        "test -f /etc/cloudflared/config.yml" 2>/dev/null; then
        echo "   Updating tunnel configuration..."
        ssh -i "${SSH_KEY_PATH}" root@${PROXMOX_HOST} "
        # Get tunnel UUID
        TUNNEL_UUID=\$(cloudflared tunnel list | grep '${TUNNEL_NAME}' | awk '{print \$1}')
        
        # Create minimal config without app routing
        cat > /etc/cloudflared/config.yml << EOF
tunnel: \$TUNNEL_UUID
credentials-file: /root/.cloudflared/\$TUNNEL_UUID.json

ingress:
  # Catch-all rule (required)
  - service: http_status:404
EOF
        
        # Restart cloudflared
        systemctl restart cloudflared
        " && echo "   ✅ Updated tunnel configuration" || echo "   (Could not update tunnel config)"
    fi
fi

# Delete the Proxmox container
echo "   Deleting Proxmox container..."
ansible localhost -m community.general.proxmox \
    -a "api_host=$PROXMOX_HOST api_user=${PROXMOX_USER:-root@pam} api_password=$PROXMOX_PASSWORD validate_certs=false vmid=${VM_ID:-200} state=absent force=true" \
    2>/dev/null || echo "   (Container may not exist or already deleted)"

# Remove local files
echo "   Cleaning up local files..."
if [[ -f "vm_ip.txt" ]]; then
    rm -f vm_ip.txt
    echo "   ✅ Removed vm_ip.txt"
fi

# Clean up any temporary files
if [[ -f "/tmp/vm_root_password" ]]; then
    rm -f "/tmp/vm_root_password"
    echo "   ✅ Removed temporary password file"
fi

echo ""
echo "✅ Cleanup completed successfully!"
echo ""
echo "🚀 To deploy again, run:"
echo "   ./deploy-and-expose.sh"
echo ""
echo "💡 The dedicated Proxmox SSH key ($HOME/.ssh/id_proxmox) has been preserved for future deployments."
