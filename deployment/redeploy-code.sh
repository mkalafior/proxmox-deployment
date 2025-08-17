#!/bin/bash

# Code Redeployment Script - Update code without recreating VM
# Usage: ./redeploy-code.sh

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

echo "🔄 Code Redeployment Script"
echo "==========================="

# Check if we're in the right directory
if [[ ! -f "redeploy.yml" ]]; then
    log_error "Please run this script from the deployment directory"
    echo "   cd deployment && ./redeploy-code.sh"
    exit 1
fi

# Check if deployment exists
if [[ ! -f "vm_ip.txt" ]]; then
    log_error "No existing deployment found"
    echo "   Run ./deploy-and-expose.sh first to create initial deployment"
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

# Get current VM IP
get_vm_info() {
    log_step "Getting current deployment information..."
    
    VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')
    log_info "Current VM IP: ${VM_IP}"
    
    # Note: Ansible will handle SSH connectivity automatically
    # No need for manual SSH testing - Ansible is configured with proper SSH settings
}

# Test current application status
test_current_app() {
    log_step "Testing current application status..."
    
    # Test local connectivity
    if curl -s --connect-timeout 5 "http://${VM_IP}:${APP_PORT}/health" > /dev/null; then
        log_info "✅ Current application is running at http://${VM_IP}:${APP_PORT}"
    else
        log_warn "⚠ Current application may not be responding"
        log_info "Will proceed with code update..."
    fi
}

# Redeploy code using Ansible
redeploy_code() {
    log_step "Redeploying application code..."
    
    # Install required collections (in case they're missing)
    ansible-galaxy collection install -r requirements.yml --force >/dev/null 2>&1
    
    # Validate playbook
    ansible-playbook redeploy.yml --syntax-check >/dev/null
    
    # Show redeployment plan
    echo ""
    echo "🎯 Code Update Plan:"
    echo "   Target VM: ${VM_IP}"
    echo "   Application Port: ${APP_PORT}"
    echo "   Strategy: Rolling update with backup"
    echo "   SSH Key: ${SSH_KEY_PATH}"
    echo ""
    
    # Run code redeployment
    log_info "Starting code redeployment..."
    if ansible-playbook redeploy.yml -v; then
        log_info "✅ Code redeployment completed"
    else
        log_error "Code redeployment failed"
        exit 1
    fi
}

# Test updated application
test_updated_app() {
    log_step "Testing updated application..."
    
    # Wait for application to restart
    log_info "Waiting for application to restart..."
    sleep 5
    
    # Test local connectivity
    if curl -s --connect-timeout 10 "http://${VM_IP}:${APP_PORT}/health" > /dev/null; then
        log_info "✅ Updated application is running at http://${VM_IP}:${APP_PORT}"
    else
        log_warn "⚠ Updated application may not be ready yet"
        log_info "Check logs with: ./manage.sh logs"
    fi
}

# Test public URL (Cloudflare tunnel should still work)
test_public_url() {
    log_step "Testing public URL accessibility..."
    
    FINAL_URL="https://${APP_SUBDOMAIN}.${DOMAIN}"
    
    log_info "Testing public URL: $FINAL_URL"
    
    # Try to test the URL
    if curl -s --connect-timeout 10 "$FINAL_URL" > /dev/null; then
        log_info "✅ Public URL is accessible: $FINAL_URL"
    else
        log_warn "⚠ Public URL may not be responding"
        log_info "Check Cloudflare tunnel status on Proxmox server"
    fi
}

# Show final summary
show_summary() {
    echo ""
    echo "🎉 Code Redeployment Completed!"
    echo "==============================="
    echo ""
    echo "📊 Your updated application is running:"
    echo "   VM IP: ${VM_IP}"
    echo "   Local URL: http://${VM_IP}:${APP_PORT}"
    echo "   Public URL: https://${APP_SUBDOMAIN}.${DOMAIN}"
    echo ""
    echo "🔧 Management commands:"
    echo "   Check status: ./manage.sh status"
    echo "   View logs:    ./manage.sh logs"
    echo "   Restart app:  ./manage.sh restart"
    echo ""
    echo "🔍 SSH into VM:"
    echo "   ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    echo ""
    echo "💡 Your updated code is now live!"
}

# Main execution
main() {
    check_environment
    get_vm_info
    test_current_app
    redeploy_code
    test_updated_app
    test_public_url
    show_summary
}

# Run main function
main "$@"
