#!/bin/bash

# Simplified Cleanup Script for Hello World Bun App
# Usage: ./cleanup.sh

set -euo pipefail

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
echo "   • Local deployment files (vm_ip.txt)"
echo ""

# Get VM IP if available
VM_IP=""
if [[ -f "vm_ip.txt" ]]; then
    VM_IP=$(cat vm_ip.txt)
    echo "   • Target VM IP: $VM_IP"
fi

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
echo "   ./deploy.sh"
echo ""
echo "💡 The dedicated Proxmox SSH key ($HOME/.ssh/id_proxmox) has been preserved for future deployments."
