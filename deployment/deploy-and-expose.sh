#!/bin/bash

# Master Deployment Script - Deploy App and Auto-Expose via Cloudflare
# Usage: ./deploy-and-expose.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuration
TUNNEL_NAME="${TUNNEL_NAME:-proxmox-main}"
DOMAIN="${CLOUDFLARE_DOMAIN:-}"
APP_SUBDOMAIN="${APP_SUBDOMAIN:-app}"
APP_PORT="${APP_PORT:-3000}"
SSH_KEY_PATH="$HOME/.ssh/id_proxmox"

echo "🚀 Master Deployment & Auto-Exposure Script"
echo "=============================================="

# Check if we're in the right directory
if [[ ! -f "deploy.yml" ]]; then
    log_error "Please run this script from the deployment directory"
    echo "   cd deployment && ./deploy-and-expose.sh"
    exit 1
fi

# Load environment variables
if [[ -f "../env.proxmox" ]]; then
    source ../env.proxmox
    log_info "Loaded environment from env.proxmox"
else
    log_error "env.proxmox file not found"
    echo "   Please create env.proxmox file in the root directory"
    exit 1
fi

# Check required environment variables
check_environment() {
    log_step "Checking environment and prerequisites..."
    
    if [[ -z "$PROXMOX_HOST" ]]; then
        log_error "PROXMOX_HOST environment variable is not set"
        exit 1
    fi
    
    if [[ -z "$DOMAIN" ]]; then
        log_error "CLOUDFLARE_DOMAIN environment variable is not set"
        exit 1
    fi
    
    # Check authentication
    if [[ -z "$PROXMOX_PASSWORD" && ( -z "$TOKEN_ID" || -z "$TOKEN_SECRET" ) ]]; then
        log_error "No Proxmox authentication configured"
        exit 1
    fi
    
    # Check if ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible is not installed"
        exit 1
    fi
    
    # Check SSH key
    if [[ ! -f "${SSH_KEY_PATH}" ]]; then
        log_error "SSH key not found at ${SSH_KEY_PATH}"
        echo "   Run ssh-keygen -t ed25519 -f ${SSH_KEY_PATH}"
        exit 1
    fi
    
    log_info "✅ Environment checks passed"
}

# Test passwordless SSH access to Proxmox host (for Cloudflare tunnel updates)
test_ssh_access() {
    log_step "Testing SSH access to Proxmox host..."
    
    if ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes root@${PROXMOX_HOST} "echo 'SSH OK'" &>/dev/null; then
        log_info "✅ SSH access to Proxmox confirmed"
    else
        log_error "SSH key authentication to Proxmox failed"
        echo "   Run: ssh-copy-id -i ${SSH_KEY_PATH}.pub root@${PROXMOX_HOST}"
        echo "   This is needed for Cloudflare tunnel configuration updates"
        exit 1
    fi
}

# Deploy application using Ansible
deploy_application() {
    log_step "Deploying application to Proxmox..."
    
    # Install required collections
    ansible-galaxy collection install -r requirements.yml --force >/dev/null 2>&1
    
    # Validate playbook
    ansible-playbook deploy.yml --syntax-check >/dev/null
    
    # Show deployment plan
    echo ""
    echo "🎯 Deployment Plan:"
    echo "   Proxmox Host: ${PROXMOX_HOST}"
    echo "   VM ID: ${VM_ID:-200}"
    echo "   VM Name: hello-world-bun-app"
    echo "   Application Port: ${APP_PORT}"
    echo "   SSH Key: ${SSH_KEY_PATH}"
    echo ""
    
    # Run deployment
    log_info "Starting Ansible deployment..."
    if ansible-playbook deploy.yml -v; then
        log_info "✅ Application deployment completed"
    else
        log_error "Application deployment failed"
        exit 1
    fi
}

# Get VM IP from deployment
get_vm_ip() {
    log_step "Getting deployed VM IP address..."
    
    if [[ -f "vm_ip.txt" ]]; then
        VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')
        log_info "VM IP: ${VM_IP}"
        
        # Validate IP format
        if [[ ! $VM_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log_error "Invalid IP address format: $VM_IP"
            exit 1
        fi
    else
        log_error "vm_ip.txt not found - deployment may have failed"
        exit 1
    fi
}

# Test application accessibility
test_application() {
    log_step "Testing application accessibility..."
    
    # Wait for application to start
    log_info "Waiting for application to start..."
    sleep 10
    
    # Test local connectivity
    if curl -s --connect-timeout 10 "http://${VM_IP}:${APP_PORT}" > /dev/null; then
        log_info "✅ Application is accessible at http://${VM_IP}:${APP_PORT}"
    else
        log_warn "⚠ Application may not be ready yet at ${VM_IP}:${APP_PORT}"
        log_info "Continuing with Cloudflare setup..."
    fi
}

# Update Cloudflare tunnel configuration
update_cloudflare_tunnel() {
    log_step "Updating Cloudflare tunnel configuration..."
    
    # Get tunnel UUID
    TUNNEL_UUID=$(ssh -i "${SSH_KEY_PATH}" root@${PROXMOX_HOST} "cloudflared tunnel list | grep '$TUNNEL_NAME' | awk '{print \$1}'")
    
    if [[ -z "$TUNNEL_UUID" ]]; then
        log_error "Tunnel $TUNNEL_NAME not found"
        exit 1
    fi
    
    log_info "Found tunnel UUID: $TUNNEL_UUID"
    
    # Generate new tunnel configuration
    cat > "/tmp/new_tunnel_config.yml" << EOF
tunnel: $TUNNEL_UUID
credentials-file: /root/.cloudflared/$TUNNEL_UUID.json

ingress:
  # Application routing
  - hostname: ${APP_SUBDOMAIN}.${DOMAIN}
    service: http://${VM_IP}:${APP_PORT}
    originRequest:
      noTLSVerify: true
    
  # Catch-all rule (required)
  - service: http_status:404
EOF
    
    # Copy configuration to Proxmox and update
    log_info "Updating tunnel configuration on Proxmox..."
    
    # Backup current config
    ssh -i "${SSH_KEY_PATH}" root@${PROXMOX_HOST} "cp /etc/cloudflared/config.yml /etc/cloudflared/config.yml.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Upload new config
    scp -i "${SSH_KEY_PATH}" "/tmp/new_tunnel_config.yml" root@${PROXMOX_HOST}:/etc/cloudflared/config.yml
    
    # Restart cloudflared service
    log_info "Restarting cloudflared service..."
    ssh -i "${SSH_KEY_PATH}" root@${PROXMOX_HOST} "systemctl restart cloudflared"
    
    # Wait and check service status
    sleep 5
    if ssh -i "${SSH_KEY_PATH}" root@${PROXMOX_HOST} "systemctl is-active --quiet cloudflared"; then
        log_info "✅ Cloudflared service restarted successfully"
    else
        log_error "Failed to restart cloudflared service"
        exit 1
    fi
    
    # Clean up temp file
    rm -f "/tmp/new_tunnel_config.yml"
}

# Test final URL accessibility
test_final_url() {
    log_step "Testing final URL accessibility..."
    
    FINAL_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"
    
    log_info "Your application will be accessible at: $FINAL_URL"
    log_warn "Note: DNS propagation may take 2-5 minutes"
    
    # Try to test the URL
    echo ""
    echo "🧪 Testing URL accessibility..."
    for i in {1..3}; do
        echo "   Attempt $i/3..."
        if curl -s --connect-timeout 10 "$FINAL_URL" > /dev/null; then
            log_info "✅ URL is accessible: $FINAL_URL"
            break
        else
            if [[ $i -eq 3 ]]; then
                log_warn "⚠ URL not yet accessible (DNS propagation in progress)"
                log_info "Try again in a few minutes: $FINAL_URL"
            else
                sleep 10
            fi
        fi
    done
}

# Show final summary
show_summary() {
    echo ""
    echo "🎉 Deployment and Exposure Completed!"
    echo "====================================="
    echo ""
    echo "📊 Your application is now running:"
    echo "   VM IP: ${VM_IP}"
    echo "   Local URL: http://${VM_IP}:${APP_PORT}"
    echo "   Public URL: https://${APP_SUBDOMAIN}.${DOMAIN}"
    echo ""
    echo "🔧 Management commands:"
    echo "   Check status: ansible-playbook manage.yml --tags=status"
    echo "   View logs:    ansible-playbook manage.yml --tags=logs"
    echo "   Restart app:  ansible-playbook manage.yml --tags=restart"
    echo ""
    echo "🔍 SSH into VM:"
    echo "   ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    echo ""
    echo "🧹 Clean up deployment:"
    echo "   ./cleanup.sh"
    echo ""
    echo "💡 Your application is now publicly accessible!"
}

# Cleanup function
cleanup() {
    rm -f "/tmp/new_tunnel_config.yml" 2>/dev/null || true
}
trap cleanup EXIT

# Check if deployment already exists and offer options
check_existing_deployment() {
    if [[ -f "vm_ip.txt" ]]; then
        EXISTING_VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')
        log_warn "Existing deployment detected!"
        echo ""
        echo "📋 Current deployment:"
        echo "   VM IP: ${EXISTING_VM_IP}"
        echo "   Public URL: https://${APP_SUBDOMAIN}.${DOMAIN}"
        echo ""
        echo "⚠️  Running full deployment will:"
        echo "   • Potentially recreate the VM (if VM ID conflicts)"
        echo "   • Replace all application code"
        echo "   • May cause brief downtime"
        echo ""
        echo "Options:"
        echo "   1) Continue with full deployment (recreate if needed)"
        echo "   2) Code update only (recommended for code changes)"
        echo "   3) Cancel"
        echo ""
        read -p "Choose option (1/2/3): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                log_info "Continuing with full deployment..."
                return 0
                ;;
            2)
                log_info "Switching to code-only update..."
                exec ./redeploy-code.sh
                ;;
            3)
                log_info "Deployment cancelled"
                exit 0
                ;;
            *)
                log_error "Invalid option. Deployment cancelled."
                exit 1
                ;;
        esac
    fi
}

# Main execution
main() {
    check_environment
    test_ssh_access
    check_existing_deployment
    deploy_application
    get_vm_ip
    test_application
    update_cloudflare_tunnel
    test_final_url
    show_summary
}

# Run main function
main "$@"
