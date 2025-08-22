#!/bin/bash

# Service management script
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
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SSH_KEY_PATH="$HOME/.ssh/id_proxmox"

# Check if deployment exists
if [[ ! -f "vm_ip.txt" ]]; then
    log_error "No deployment found for $SERVICE_NAME. Run ./deploy.sh first"
    exit 1
fi

VM_IP=$(cat vm_ip.txt | tr -d '[:space:]')

# Source environment configuration
if [[ -f "env.service" ]]; then
    source env.service
fi

show_help() {
    echo "$SERVICE_NAME Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status    - Show service status"
    echo "  logs      - Show service logs"
    echo "  restart   - Restart the service"
    echo "  system    - Show system information"
    echo "  info      - Show deployment information"
    echo "  help      - Show this help message"
    echo ""
}

check_vm_access() {
    if ! ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes root@${VM_IP} "echo 'OK'" &>/dev/null; then
        log_error "Cannot connect to $SERVICE_NAME VM at ${VM_IP}"
        exit 1
    fi
}

show_status() {
    log_info "$SERVICE_NAME Status (VM: ${VM_IP})"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        echo '🔍 Service Status:'
        systemctl status $SERVICE_NAME --no-pager || echo 'Service not found'
        echo ''
        echo '🌐 Network Status:'
        ss -tlnp | grep :${APP_PORT:-3000} || echo 'Port not listening'
        echo ''
        echo '💾 System Resources:'
        free -h
        echo ''
        df -h /
    "
}

show_logs() {
    log_info "$SERVICE_NAME Logs (VM: ${VM_IP})"
    echo ""
    
    ssh -i "${SSH_KEY_PATH}" root@${VM_IP} "
        echo '📝 Recent Application Logs:'
        journalctl -u $SERVICE_NAME --no-pager -n 50
    "
}

detect_service_info() {
    SERVICE_TYPE="$(grep -E '^service_type:' service-config.yml 2>/dev/null | awk -F: '{print $2}' | xargs || true)"
    if [[ -z "${SERVICE_TYPE}" ]]; then SERVICE_TYPE="nodejs"; fi
    RUNTIME_VARIANT_CFG="$(grep -E '^(runtime_variant|db_type):' service-config.yml 2>/dev/null | head -n1 | awk -F: '{print $2}' | xargs || true)"
    APP_UNIT_NAME="$(grep -E '^app_service_name:' service-config.yml 2>/dev/null | awk -F: '{print $2}' | xargs || true)"
    if [[ -z "${APP_UNIT_NAME}" ]]; then APP_UNIT_NAME="$SERVICE_NAME"; fi
}

restart_units() {
    detect_service_info
    local units_str="${APP_UNIT_NAME}"
    read -r -a units <<< "$units_str"
    log_info "Restarting units: ${units[*]}"
    for u in "${units[@]}"; do
      ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no root@${VM_IP} "systemctl restart $u && systemctl status $u --no-pager | head -n 8" || {
        log_error "Failed to restart unit: $u"; exit 1;
      }
    done
    log_info "Restart completed"
}

restart_service() {
    log_info "Restarting $SERVICE_NAME (VM: ${VM_IP})"
    TYPE_DIR="${SCRIPT_DIR}/../../deployment-templates/service-types"
    SERVICE_TYPE_CFG=$(grep -E '^service_type:' service-config.yml 2>/dev/null | awk -F: '{print $2}' | xargs || true)
    if [[ -n "${SERVICE_TYPE_CFG}" && -f "${TYPE_DIR}/${SERVICE_TYPE_CFG}/restart.yml.j2" ]]; then
        TMP_RESTART="/tmp/${SERVICE_NAME}-restart.yml"
        sed "s/{{ service_name }}/${SERVICE_NAME}/g" "${TYPE_DIR}/${SERVICE_TYPE_CFG}/restart.yml.j2" > "$TMP_RESTART"
        cat > /tmp/inventory.ini <<EOF_INV
[proxmox_containers]
${VM_IP} ansible_user=root ansible_ssh_private_key_file=${SSH_KEY_PATH}
EOF_INV
        ansible-playbook -i /tmp/inventory.ini "$TMP_RESTART"
        rm -f "$TMP_RESTART" /tmp/inventory.ini
        log_info "Restart via Ansible completed"
    else
        restart_units
    fi
}

show_system_info() {
    log_info "$SERVICE_NAME System Information (VM: ${VM_IP})"
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
        ps aux | grep -E '(bun|node|$SERVICE_NAME)' | grep -v grep || echo 'No application processes found'
    "
}

show_deployment_info() {
    echo "📋 $SERVICE_NAME Deployment Information"
    echo "======================================="
    echo ""
    echo "VM IP: ${VM_IP}"
    
    if [[ -f "env.service" ]]; then
        source env.service
        echo "Application Port: ${APP_PORT}"
        echo "Service Name: ${SERVICE_NAME}"
        
        if [[ -f "../../global-config/env.proxmox.global" ]]; then
            source ../../global-config/env.proxmox.global
            if [[ -n "${CLOUDFLARE_DOMAIN:-}" ]]; then
                echo "Public URL: https://${APP_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"
            fi
        fi
    fi
    
    echo ""
    echo "🔗 Quick Links:"
    echo "  Local: http://${VM_IP}:${APP_PORT:-3000}"
    echo "  Health: http://${VM_IP}:${APP_PORT:-3000}/health"
    echo ""
    echo "🔧 Management:"
    echo "  SSH: ssh -i ~/.ssh/id_proxmox root@${VM_IP}"
    echo "  Logs: ./manage.sh logs"
    echo "  Status: ./manage.sh status"
    echo "  Restart: ./manage.sh restart"
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
        restart_service
        ;;
    system)
        check_vm_access
        show_system_info
        ;;
    info)
        show_deployment_info
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
