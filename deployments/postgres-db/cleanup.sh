#!/bin/bash

# Service cleanup script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🧹 Cleanup $SERVICE_NAME Deployment"
echo "===================================="

# Load configurations
if [[ -f "../../global-config/env.proxmox.global" ]]; then
    source ../../global-config/env.proxmox.global
fi

if [[ -f "env.service" ]]; then
    source env.service
fi

if [[ ! -f "vm_ip.txt" ]]; then
    log_warn "No deployment found for $SERVICE_NAME"
    exit 0
fi

VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')

echo "⚠️  This will permanently delete:"
echo "   • VM/Container with ID: ${VM_ID}"
echo "   • All data in the container"
echo "   • Service configuration"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r

if [[ "$REPLY" != "yes" ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

log_info "Stopping container..."

# Stop container
STOP_RESPONSE=$(curl -k -s -X POST \
  -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
  "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/lxc/${VM_ID}/status/stop" 2>/dev/null || echo '{"errors":["Failed to stop"]}')

if echo "$STOP_RESPONSE" | grep -q '"data"'; then
    log_info "Container stopped successfully"
else
    log_warn "Container may already be stopped"
fi

sleep 5

log_info "Removing container..."

# Remove container
DELETE_RESPONSE=$(curl -k -s -X DELETE \
  -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
  "https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_NODE}/lxc/${VM_ID}" 2>/dev/null || echo '{"errors":["Failed to delete"]}')

if echo "$DELETE_RESPONSE" | grep -q '"data"'; then
    log_info "Container removed successfully"
else
    log_error "Failed to remove container - it may not exist"
fi

# Clean up local files
rm -f vm_ip.txt

log_info "✅ $SERVICE_NAME cleanup completed"
