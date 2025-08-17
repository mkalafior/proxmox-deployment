#!/bin/bash

# Application Management Script
# Usage: ./manage.sh [status|logs|restart|system|info]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SSH_KEY_PATH="$HOME/.ssh/id_proxmox"

# Check if deployment exists
if [[ ! -f "vm_ip.txt" ]]; then
    log_error "No deployment found. Run ./deploy-and-expose.sh first"
    exit 1
fi

VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')

show_help() {
    echo "Application Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status    - Show application and system status"
    echo "  logs      - Show application logs"
    echo "  restart   - Restart the application service"
    echo "  system    - Show system information"
    echo "  info      - Show deployment information"
    echo "  update    - Update application code only (no VM recreation)"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 logs"
    echo "  $0 restart"
    echo "  $0 update"
}

check_vm_access() {
    if ! ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes root@${VM_IP} "echo 'OK'" &>/dev/null; then
        log_error "Cannot connect to VM at ${VM_IP}"
        echo "   Check if VM is running and SSH key is configured"
        exit 1
    fi
}

show_status() {
    log_info "Application Status for VM: ${VM_IP}"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        echo '🔍 Service Status:'
        systemctl status hello-world-bun-app --no-pager || echo 'Service not found'
        echo ''
        echo '🌐 Network Status:'
        ss -tlnp | grep :3000 || echo 'Port 3000 not listening'
        echo ''
        echo '💾 System Resources:'
        free -h
        echo ''
        df -h /
    "
}

show_logs() {
    log_info "Application Logs for VM: ${VM_IP}"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        echo '📝 Recent Application Logs:'
        journalctl -u hello-world-bun-app --no-pager -n 50
    "
}

restart_app() {
    log_info "Restarting application on VM: ${VM_IP}"
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        systemctl restart hello-world-bun-app
        sleep 3
        systemctl status hello-world-bun-app --no-pager
    "
    
    log_info "✅ Application restarted"
}

show_system_info() {
    log_info "System Information for VM: ${VM_IP}"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        echo '🖥️  System Information:'
        uname -a
        echo ''
        echo '🕒 Uptime:'
        uptime
        echo ''
        echo '💾 Memory Usage:'
        free -h
        echo ''
        echo '💽 Disk Usage:'
        df -h
        echo ''
        echo '🔄 Running Processes:'
        ps aux | grep -E '(bun|node|hello-world)' | grep -v grep || echo 'No application processes found'
    "
}

show_deployment_info() {
    echo "📋 Deployment Information"
    echo "========================"
    echo ""
    echo "VM IP: ${VM_IP}"
    echo "Application Port: 3000"
    
    if [[ -f "../env.proxmox" ]]; then
        source ../env.proxmox
        if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
            echo "Public URL: https://${APP_SUBDOMAIN:-app}.${CLOUDFLARE_DOMAIN}"
        fi
    fi
    
    echo ""
    echo "🔗 Quick Links:"
    echo "  Local: http://${VM_IP}:3000"
    echo "  Health: http://${VM_IP}:3000/health"
    echo "  API Info: http://${VM_IP}:3000/api/info"
    echo ""
    echo "🔧 Management:"
    echo "  SSH: ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    echo "  Logs: ./manage.sh logs"
    echo "  Status: ./manage.sh status"
    echo "  Restart: ./manage.sh restart"
}

# Update application code
update_code() {
    log_info "Starting code update..."
    exec ./redeploy-code.sh
}

# Main execution
case "${1:-help}" in
    status)
        check_vm_access
        show_status
        ;;
    logs)
        check_vm_access
        show_logs
        ;;
    restart)
        check_vm_access
        restart_app
        ;;
    system)
        check_vm_access
        show_system_info
        ;;
    info)
        show_deployment_info
        ;;
    update)
        update_code
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
