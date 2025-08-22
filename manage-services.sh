#!/bin/bash

# Multi-Service Management Script for Proxmox Monorepo
# Usage: ./manage-services.sh [COMMAND] [SERVICE]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_service() { echo -e "${CYAN}[SERVICE]${NC} $1"; }

show_help() {
    echo "Multi-Service Management Script"
    echo ""
    echo "Usage: $0 [COMMAND] [SERVICE]"
    echo ""
    echo "Commands:"
    echo "  list              - List all available services"
    echo "  status [SERVICE]  - Show status of service(s)"
    echo "  deploy [SERVICE]  - Deploy service(s)"
    echo "  logs [SERVICE]    - Show logs for service(s)"
    echo "  restart [SERVICE] - Restart service(s)"
    echo "  cleanup [SERVICE] - Cleanup service(s)"
    echo "  generate SERVICE  - Generate new service deployment"
    echo "  info [SERVICE]    - Show service information"
    echo "  help              - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list                    # List all services"
    echo "  $0 status                  # Status of all services"
    echo "  $0 status service01        # Status of service01 only"
    echo "  $0 deploy service01        # Deploy service01"
    echo "  $0 generate new-service    # Generate deployment for new-service"
    echo ""
    echo "Service Management:"
    echo "  If SERVICE is not specified, command applies to all services"
    echo "  Services are auto-discovered from deployments/ directory"
}

# Get list of available services
get_services() {
    if [[ -d "deployments" ]]; then
        find deployments -maxdepth 1 -type d -not -name "deployments" -exec basename {} \; | sort
    else
        echo ""
    fi
}

# Check if service exists
service_exists() {
    local service="$1"
    [[ -d "deployments/$service" ]]
}

# Execute command for a single service
execute_service_command() {
    local service="$1"
    local command="$2"
    
    if ! service_exists "$service"; then
        log_error "Service '$service' not found"
        return 1
    fi
    
    local service_dir="deployments/$service"
    
    case "$command" in
        status|logs|restart|info)
            if [[ -f "$service_dir/manage.sh" ]]; then
                log_service "Executing $command for $service"
                (cd "$service_dir" && ./manage.sh "$command")
            else
                log_error "Management script not found for $service"
                return 1
            fi
            ;;
        deploy)
            if [[ -f "$service_dir/deploy.sh" ]]; then
                log_service "Deploying $service"
                (cd "$service_dir" && ./deploy.sh)
            else
                log_error "Deploy script not found for $service"
                return 1
            fi
            ;;
        cleanup)
            if [[ -f "$service_dir/cleanup.sh" ]]; then
                log_service "Cleaning up $service"
                (cd "$service_dir" && ./cleanup.sh)
            else
                log_error "Cleanup script not found for $service"
                return 1
            fi
            ;;
        *)
            log_error "Unknown command: $command"
            return 1
            ;;
    esac
}

# List all services
list_services() {
    echo "📋 Available Services"
    echo "===================="
    echo ""
    
    local services
    services=$(get_services)
    
    if [[ -z "$services" ]]; then
        log_warn "No services found in deployments/ directory"
        echo ""
        echo "💡 Generate a new service with:"
        echo "   $0 generate <service-name>"
        return 0
    fi
    
    echo "$services" | while read -r service; do
        if [[ -n "$service" ]]; then
            echo "🔹 $service"
            
            # Show basic info if available
            if [[ -f "deployments/$service/env.service" ]]; then
                source "deployments/$service/env.service" 2>/dev/null || true
                echo "   VM ID: ${VM_ID:-unknown}"
                echo "   Port: ${APP_PORT:-unknown}"
                echo "   Subdomain: ${APP_SUBDOMAIN:-unknown}"
            fi
            
            # Check if deployed
            if [[ -f "deployments/$service/vm_ip.txt" ]]; then
                local vm_ip
                vm_ip=$(cat "deployments/$service/vm_ip.txt" | tr -d '[:space:]')
                echo "   Status: 🟢 Deployed (IP: $vm_ip)"
            else
                echo "   Status: ⚪ Not deployed"
            fi
            echo ""
        fi
    done
}

# Show status for all services
status_all() {
    log_step "Checking status of all services..."
    echo ""
    
    local services
    services=$(get_services)
    
    if [[ -z "$services" ]]; then
        log_warn "No services found"
        return 0
    fi
    
    echo "$services" | while read -r service; do
        if [[ -n "$service" ]]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            execute_service_command "$service" "status" || true
            echo ""
        fi
    done
}

# Deploy all services
deploy_all() {
    log_step "Deploying all services..."
    echo ""
    
    local services
    services=$(get_services)
    
    if [[ -z "$services" ]]; then
        log_warn "No services found"
        return 0
    fi
    
    echo "$services" | while read -r service; do
        if [[ -n "$service" ]]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            execute_service_command "$service" "deploy" || true
            echo ""
        fi
    done
}

# Generate new service
generate_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required for generate command"
        echo ""
        echo "Usage: $0 generate <service-name>"
        echo ""
        echo "Example: $0 generate my-new-service"
        return 1
    fi
    
    if service_exists "$service_name"; then
        log_warn "Service '$service_name' already exists"
        echo ""
        read -p "Overwrite existing service? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Generation cancelled"
            return 0
        fi
    fi
    
    # Interactive generation
    echo "🚀 Generating new service: $service_name"
    echo "========================================"
    echo ""
    
    # Get VM ID
    local vm_id
    while true; do
        read -p "VM ID (e.g., 203): " vm_id
        if [[ "$vm_id" =~ ^[0-9]+$ ]]; then
            break
        else
            log_error "VM ID must be a number"
        fi
    done
    
    # Get port
    local app_port
    while true; do
        read -p "Application port (e.g., 3003): " app_port
        if [[ "$app_port" =~ ^[0-9]+$ ]]; then
            break
        else
            log_error "Port must be a number"
        fi
    done
    
    # Get subdomain (optional). If left blank, keep empty (no default)
    local app_subdomain
    read -p "Cloudflare subdomain (optional, leave blank to disable): " app_subdomain
    
    # Get hostname (optional)
    local service_hostname
    read -p "Service hostname (optional, default: $service_name): " service_hostname
    if [[ -z "$service_hostname" ]]; then
        service_hostname="$service_name"
    fi
    
    # Ask for service type and optional runtime/db type
    local service_type
    read -p "Service type (nodejs/python/golang/rust/database/static/tor-proxy): " service_type
    # Normalize to lowercase in a way compatible with older macOS bash
    service_type=$(echo "$service_type" | tr '[:upper:]' '[:lower:]')
    local runtime_variant=""
    if [[ "$service_type" == "nodejs" ]]; then
        read -p "Node runtime (node/bun) [bun]: " runtime_variant
        runtime_variant=${runtime_variant:-bun}
    elif [[ "$service_type" == "database" ]]; then
        read -p "Database type (postgresql/mysql/redis/mongodb) [postgresql]: " runtime_variant
        runtime_variant=${runtime_variant:-postgresql}
    fi

    # Run enhanced multi-service generator
    log_step "Running service generator..."
    if [[ -f "deployment-templates/generators/generate-multi-service.sh" ]]; then
        cmd=("./deployment-templates/generators/generate-multi-service.sh" "$service_name" --type "$service_type" --vm-id "$vm_id" --port "$app_port" --hostname "$service_hostname" --force)
        if [[ -n "$runtime_variant" ]]; then
            cmd+=(--runtime "$runtime_variant")
        fi
        if [[ -n "$app_subdomain" ]]; then
            cmd+=(--subdomain "$app_subdomain")
        fi
        "${cmd[@]}"
    else
        log_error "Multi-service generator not found"
        return 1
    fi
}

# Main execution
COMMAND="${1:-help}"
SERVICE="${2:-}"

case "$COMMAND" in
    list)
        list_services
        ;;
    status)
        if [[ -n "$SERVICE" ]]; then
            execute_service_command "$SERVICE" "status"
        else
            status_all
        fi
        ;;
    deploy)
        if [[ -n "$SERVICE" ]]; then
            execute_service_command "$SERVICE" "deploy"
        else
            deploy_all
        fi
        ;;
    logs)
        if [[ -n "$SERVICE" ]]; then
            execute_service_command "$SERVICE" "logs"
        else
            log_error "Service name required for logs command"
            echo "Usage: $0 logs <service-name>"
            exit 1
        fi
        ;;
    restart)
        if [[ -n "$SERVICE" ]]; then
            execute_service_command "$SERVICE" "restart"
        else
            log_error "Service name required for restart command"
            echo "Usage: $0 restart <service-name>"
            exit 1
        fi
        ;;
    cleanup)
        if [[ -n "$SERVICE" ]]; then
            execute_service_command "$SERVICE" "cleanup"
        else
            log_error "Service name required for cleanup command"
            echo "Usage: $0 cleanup <service-name>"
            exit 1
        fi
        ;;
    generate)
        generate_service "$SERVICE"
        ;;
    info)
        if [[ -n "$SERVICE" ]]; then
            execute_service_command "$SERVICE" "info"
        else
            log_error "Service name required for info command"
            echo "Usage: $0 info <service-name>"
            exit 1
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
