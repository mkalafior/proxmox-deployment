#!/bin/bash

# Multi-Language Service Deployment Generator
# Usage: ./generate-multi-service.sh <service-name> --type <service-type> [options]

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
log_type() { echo -e "${CYAN}[TYPE]${NC} $1"; }

# Proxmox API functions
fetch_proxmox_nodes() {
    if [[ -z "${PROXMOX_HOST:-}" ]]; then
        log_error "PROXMOX_HOST not set. Please configure your Proxmox connection."
        exit 1
    fi

    if [[ -z "${TOKEN_ID:-}" || -z "${TOKEN_SECRET:-}" ]]; then
        log_error "TOKEN_ID and TOKEN_SECRET not set. Please configure your Proxmox API token."
        exit 1
    fi

    log_step "Fetching available Proxmox nodes..."

    local response
    response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to connect to Proxmox API"
        exit 1
    fi

    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.data[] | "\(.node)"' 2>/dev/null || echo ""
    else
        # Fallback parsing without jq
        echo "$response" | grep -o '"node":"[^"]*"' | cut -d'"' -f4 || echo ""
    fi
}

fetch_vm_ids_from_node() {
    local node="$1"

    if [[ -z "$node" ]]; then
        log_error "Node name is required"
        return 1
    fi

    log_step "Fetching VM IDs from node $node..."

    local response
    response=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/nodes/$node/qemu" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch VMs from node $node"
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.data[] | "\(.vmid)"' 2>/dev/null | sort -n || echo ""
    else
        # Fallback parsing without jq
        echo "$response" | grep -o '"vmid":[0-9]*' | cut -d':' -f2 | sort -n || echo ""
    fi
}

find_first_available_vmid() {
    local node="$1"
    # Prefer cluster-wide nextid endpoint
    if [[ -n "${PROXMOX_HOST:-}" && -n "${TOKEN_ID:-}" && -n "${TOKEN_SECRET:-}" ]]; then
        local resp nextid
        resp=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
            -X POST "https://${PROXMOX_HOST}:8006/api2/json/cluster/nextid" 2>/dev/null || true)
        if [[ "$resp" == *"\"data\":"* ]]; then
            nextid=$(echo "$resp" | sed -n 's/.*"data"\s*:\s*"\?\([0-9]\+\)"\?.*/\1/p' | head -n1)
            if [[ -n "$nextid" ]]; then
                echo "$nextid"
                return 0
            fi
        fi
    fi

    # Fallback: compute across cluster resources
    local resources used vmid
    resources=$(curl -ks -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/cluster/resources?type=vm" 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1; then
        used=$(echo "$resources" | jq -r '.data[].vmid' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | uniq)
    else
        used=$(echo "$resources" | grep -o '"vmid"\s*:\s*[0-9]\+' | grep -o '[0-9]\+' | sort -n | uniq)
    fi
    vmid=100
    while [[ $vmid -lt 10000 ]]; do
        if ! echo "$used" | grep -qx "$vmid"; then
            echo "$vmid"
            return 0
        fi
        ((vmid++))
    done
    log_error "No available VMID found cluster-wide (100-9999)"
    return 1
}

select_proxmox_node() {
    local nodes
    nodes=$(fetch_proxmox_nodes)

    if [[ -z "$nodes" ]]; then
        log_error "No Proxmox nodes found or unable to connect"
        exit 1
    fi

    # Convert to array
    local node_array=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            node_array+=("$line")
        fi
    done <<< "$nodes"

    if [[ ${#node_array[@]} -eq 1 ]]; then
        log_info "Using single available node: ${node_array[0]}"
        echo "${node_array[0]}"
        return 0
    fi

    echo ""
    echo "Available Proxmox nodes:"
    for i in "${!node_array[@]}"; do
        echo "  $((i+1)). ${node_array[$i]}"
    done
    echo ""

    local choice
    while true; do
        read -p "Select node (1-${#node_array[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#node_array[@]} ]]; then
            echo "${node_array[$((choice-1))]}"
            return 0
        else
            echo "Invalid choice. Please select a number between 1 and ${#node_array[@]}."
        fi
    done
}

# Available service types
AVAILABLE_TYPES=("nodejs" "python" "golang" "rust" "database" "static" "tor-proxy")

show_help() {
    echo "Multi-Language Service Deployment Generator"
    echo ""
    echo "Usage: $0 <service-name> --type <service-type> [options]"
    echo ""
    echo "Arguments:"
    echo "  service-name    Name of the service to generate deployment for"
    echo ""
    echo "Required Options:"
    echo "  --type TYPE     Service type: ${AVAILABLE_TYPES[*]}"
    echo "  --port PORT     Application port"
    echo ""
    echo "Service Type Options:"
    echo "  --runtime RT    Runtime variant (nodejs: node|bun, database: postgresql|mysql|redis|mongodb)"
    echo "  --main-file F   Main application file (default varies by type)"
    echo "  --db-name NAME  Database name (for database type)"
    echo "  --db-user USER  Database user (for database type)"
    echo "  --db-pass PASS  Database password (for database type)"
    echo ""
    echo "General Options:"
    echo "  --node NODE     Proxmox node (optional, will prompt for selection)"
    echo "  --vm-id ID      VM ID for Proxmox (optional, will auto-select first available)"
    echo "  --subdomain SUB Cloudflare subdomain (optional)"
    echo "  --hostname HOST Service hostname for DNS (optional, defaults to service-name)"
    echo "  --cores N       CPU cores (default: 2)"
    echo "  --memory MB     Memory in MB (default: 2048)"
    echo "  --disk GB       Disk size in GB (default: 20)"
    echo "  --user USER     Application user (default: appuser)"
    echo "  --force         Overwrite existing deployment"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Node.js with Bun"
    echo "  $0 api-service --type nodejs --runtime bun --vm-id 201 --port 3001"
    echo ""
    echo "  # Python FastAPI"
    echo "  $0 python-api --type python --vm-id 202 --port 8000 --main-file app.py"
    echo ""
    echo "  # Go microservice"
    echo "  $0 go-service --type golang --vm-id 203 --port 8080"
    echo ""
    echo "  # PostgreSQL database"
    echo "  $0 postgres-db --type database --runtime postgresql --vm-id 204 --port 5432 --db-name myapp --db-user myuser --db-pass secret123"
    echo ""
    echo "  # Static website"
    echo "  $0 frontend --type static --vm-id 205 --port 80"
    echo ""
    echo "Service Types:"
    echo "  nodejs    - Node.js/Bun.js applications"
    echo "  python    - Python applications (Flask, FastAPI, Django)"
    echo "  golang    - Go applications"
    echo "  rust      - Rust applications"
    echo "  database  - Database services (PostgreSQL, MySQL, Redis, MongoDB)"
    echo "  static    - Static websites (Nginx)"
}

# Parse command line arguments
SERVICE_NAME=""
SERVICE_TYPE=""
RUNTIME_VARIANT=""
VM_ID=""
PROXMOX_NODE=""
APP_PORT=""
APP_SUBDOMAIN=""
SERVICE_HOSTNAME=""
VM_CORES="2"
VM_MEMORY="2048"
VM_DISK_SIZE="20"
APP_USER="appuser"
APP_MAIN_FILE=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
FORCE_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            SERVICE_TYPE="$2"
            shift 2
            ;;
        --runtime)
            RUNTIME_VARIANT="$2"
            shift 2
            ;;
        --vm-id)
            VM_ID="$2"
            shift 2
            ;;
        --node)
            PROXMOX_NODE="$2"
            shift 2
            ;;
        --port)
            APP_PORT="$2"
            shift 2
            ;;
        --subdomain)
            APP_SUBDOMAIN="$2"
            shift 2
            ;;
        --hostname)
            SERVICE_HOSTNAME="$2"
            shift 2
            ;;
        --cores)
            VM_CORES="$2"
            shift 2
            ;;
        --memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        --disk)
            VM_DISK_SIZE="$2"
            shift 2
            ;;
        --user)
            APP_USER="$2"
            shift 2
            ;;
        --main-file)
            APP_MAIN_FILE="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --db-user)
            DB_USER="$2"
            shift 2
            ;;
        --db-pass)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$SERVICE_NAME" ]]; then
                SERVICE_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate or prompt for required arguments
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Service name is required"
    show_help
    exit 1
fi

if [[ -z "$SERVICE_TYPE" ]]; then
    echo -n "Service type (${AVAILABLE_TYPES[*]}): "
    read -r SERVICE_TYPE
fi

if [[ ! " ${AVAILABLE_TYPES[*]} " =~ " ${SERVICE_TYPE} " ]]; then
    log_error "Invalid service type: $SERVICE_TYPE"
    log_error "Available types: ${AVAILABLE_TYPES[*]}"
    exit 1
fi

if [[ -z "$APP_PORT" ]]; then
    echo -n "Application port: "
    read -r APP_PORT
fi

# Load environment configuration if available
if [[ -f "$HOME/.pxdcli/env.global" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.pxdcli/env.global"
fi

# Handle node selection
if [[ -z "$PROXMOX_NODE" ]]; then
    PROXMOX_NODE=$(select_proxmox_node)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
fi

# Handle VM ID selection
if [[ -z "$VM_ID" ]]; then
    VM_ID=$(find_first_available_vmid "$PROXMOX_NODE")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    log_info "Auto-selected VM ID: $VM_ID on node $PROXMOX_NODE"
else
    log_info "Using specified VM ID: $VM_ID on node $PROXMOX_NODE"
fi

# Set defaults based on service type
if [[ -z "$SERVICE_HOSTNAME" ]]; then
    SERVICE_HOSTNAME="$SERVICE_NAME"
fi
# Do NOT default APP_SUBDOMAIN; keep it empty when user leaves blank

# Set runtime defaults
case "$SERVICE_TYPE" in
    nodejs)
        if [[ -z "$RUNTIME_VARIANT" ]]; then
            echo -n "Node runtime (node/bun) [bun]: "
            read -r RUNTIME_VARIANT
            RUNTIME_VARIANT="${RUNTIME_VARIANT:-bun}"
        fi
        APP_MAIN_FILE="${APP_MAIN_FILE:-index.js}"
        ;;
    python)
        RUNTIME_VARIANT="${RUNTIME_VARIANT:-python3}"
        APP_MAIN_FILE="${APP_MAIN_FILE:-main.py}"
        ;;
    golang)
        RUNTIME_VARIANT="${RUNTIME_VARIANT:-go}"
        APP_MAIN_FILE="${APP_MAIN_FILE:-.}"
        ;;
    database)
        # If not provided, prompt for DB type
        if [[ -z "$RUNTIME_VARIANT" ]]; then
            echo -n "Database type (postgresql/mysql/redis/mongodb) [postgresql]: "
            read -r RUNTIME_VARIANT
            RUNTIME_VARIANT="${RUNTIME_VARIANT:-postgresql}"
        fi
        DB_NAME="${DB_NAME:-$SERVICE_NAME}"
        DB_USER="${DB_USER:-$SERVICE_NAME}"
        if [[ -z "$DB_PASSWORD" ]]; then
            DB_PASSWORD=$(openssl rand -base64 32)
            log_info "Generated database password: $DB_PASSWORD"
        fi
        ;;
    static)
        RUNTIME_VARIANT="${RUNTIME_VARIANT:-nginx}"
        APP_MAIN_FILE="${APP_MAIN_FILE:-index.html}"
        ;;
    tor-proxy)
        RUNTIME_VARIANT="${RUNTIME_VARIANT:-tor}"
        APP_MAIN_FILE="${APP_MAIN_FILE:-}"
        ;;
esac

# Roots: support global templates and external target projects
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TEMPLATES_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_ROOT="${TEMPLATES_ROOT:-${DEFAULT_TEMPLATES_ROOT}}"
TEMPLATES_BASE="${TEMPLATES_ROOT}/deployment-templates"

TARGET_PROJECT_ROOT="${PROJECT_ROOT_OVERRIDE:-${TEMPLATES_ROOT%/deployment-templates}}"
if [[ ! -d "$TEMPLATES_BASE/service-types" ]]; then
    log_error "Cannot find service type templates at $TEMPLATES_BASE/service-types"
    exit 1
fi

# Set up paths
DEPLOYMENT_DIR="$TARGET_PROJECT_ROOT/deployments/$SERVICE_NAME"
SERVICE_DIR="$TARGET_PROJECT_ROOT/services/$SERVICE_NAME"
SERVICE_TYPE_DIR="$TEMPLATES_BASE/service-types/$SERVICE_TYPE"

if [[ ! -d "$SERVICE_TYPE_DIR" ]]; then
    log_error "Service type '$SERVICE_TYPE' not found in templates"
    exit 1
fi

echo "🚀 Multi-Language Service Generator"
echo "===================================="
echo ""
echo "📋 Configuration:"
echo "   Service Name: $SERVICE_NAME"
echo "   Service Type: $SERVICE_TYPE ($RUNTIME_VARIANT)"
echo "   Proxmox Node: $PROXMOX_NODE"
echo "   VM ID: $VM_ID"
echo "   App Port: $APP_PORT"
echo "   Main File: $APP_MAIN_FILE"
if [[ "$SERVICE_TYPE" == "database" ]]; then
    echo "   Database: $DB_NAME"
    echo "   DB User: $DB_USER"
fi
echo "   VM Cores: $VM_CORES"
echo "   VM Memory: ${VM_MEMORY}MB"
echo ""

# Check if deployment already exists
if [[ -d "$DEPLOYMENT_DIR" ]] && [[ "$FORCE_OVERWRITE" != "true" ]]; then
    log_warn "Deployment directory already exists: $DEPLOYMENT_DIR"
    echo ""
    read -p "Overwrite existing deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Generation cancelled"
        exit 0
    fi
fi

# Create service directory and starter files
create_service_starter() {
    if [[ -d "$SERVICE_DIR" ]]; then
        log_step "Service directory already exists, skipping starter scaffolding: $SERVICE_DIR"
        return 0
    fi

    log_step "Creating service starter files..."
    
    # Use template-based service creation for better maintainability
    local template_args=(
        "app_port=$APP_PORT"
    )
    
    # Add runtime-specific variables
    case "$SERVICE_TYPE" in
        nodejs)
            template_args+=("nodejs_runtime=$RUNTIME_VARIANT")
            ;;
        python)
            template_args+=("runtime_variant=$RUNTIME_VARIANT")
            ;;
        golang)
            template_args+=("runtime_variant=$RUNTIME_VARIANT")
            ;;
        *)
            template_args+=("runtime_variant=$RUNTIME_VARIANT")
            ;;
    esac
    
    # Check if template-based service creation is available
    local create_script="$SCRIPT_DIR/create-service-from-template.sh"
    if [[ -f "$create_script" ]]; then
        if "$create_script" "$SERVICE_NAME" "$SERVICE_TYPE" "$SERVICE_DIR" "${template_args[@]}"; then
            log_info "✅ Created $SERVICE_TYPE service starter files"
            return 0
        else
            log_warn "Template-based creation failed, falling back to legacy method"
        fi
    fi
    
    # Fallback to legacy hardcoded creation (only for unsupported service types)
    log_warn "Using legacy service creation - template system not available"
    mkdir -p "$SERVICE_DIR"
    
    case "$SERVICE_TYPE" in
        nodejs)
            if [[ "$RUNTIME_VARIANT" == "bun" ]]; then
                cat > "$SERVICE_DIR/package.json" << EOF
{
  "name": "$SERVICE_NAME",
  "version": "1.0.0",
  "description": "$SERVICE_TYPE service: $SERVICE_NAME",
  "main": "$APP_MAIN_FILE",
  "scripts": {
    "start": "bun run $APP_MAIN_FILE",
    "dev": "bun run --watch $APP_MAIN_FILE"
  },
  "dependencies": {}
}
EOF

                cat > "$SERVICE_DIR/$APP_MAIN_FILE" << EOF
// $SERVICE_TYPE service: $SERVICE_NAME
const server = Bun.serve({
  port: process.env.PORT || $APP_PORT,
  hostname: process.env.HOST || "0.0.0.0",
  fetch(req) {
    const url = new URL(req.url);
    
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({
        status: "healthy",
        service: "$SERVICE_NAME",
        type: "$SERVICE_TYPE",
        runtime: "$RUNTIME_VARIANT",
        timestamp: new Date().toISOString()
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    if (url.pathname === "/") {
      return new Response(JSON.stringify({
        message: "Hello from $SERVICE_NAME!",
        service: "$SERVICE_NAME",
        type: "$SERVICE_TYPE",
        port: server.port
      }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not Found", { status: 404 });
  },
});

console.log(`🚀 $SERVICE_NAME ($SERVICE_TYPE) running on http://${server.hostname}:${server.port}`);
EOF
            else
                cat > "$SERVICE_DIR/package.json" << EOF
{
  "name": "$SERVICE_NAME",
  "version": "1.0.0",
  "description": "$SERVICE_TYPE service: $SERVICE_NAME",
  "main": "$APP_MAIN_FILE",
  "scripts": {
    "start": "node $APP_MAIN_FILE"
  },
  "dependencies": {}
}
EOF
                cat > "$SERVICE_DIR/$APP_MAIN_FILE" << EOF
// $SERVICE_TYPE service: $SERVICE_NAME
const http = require('http');

const port = process.env.PORT || $APP_PORT;
const host = process.env.HOST || '0.0.0.0';

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  res.setHeader('Content-Type', 'application/json');

  if (url.pathname === '/health') {
    res.end(JSON.stringify({ status: 'healthy', service: '$SERVICE_NAME', type: '$SERVICE_TYPE', runtime: '$RUNTIME_VARIANT' }));
    return;
  }

  if (url.pathname === '/') {
    res.end(JSON.stringify({ message: 'Hello from $SERVICE_NAME!', service: '$SERVICE_NAME', type: '$SERVICE_TYPE', runtime: '$RUNTIME_VARIANT', port }));
    return;
  }

  res.statusCode = 404;
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(port, host, () => {
  console.log(`🚀 $SERVICE_NAME ($SERVICE_TYPE) running on http://${host}:${port}`);
});
EOF
            fi
            ;;
            
        python)
            cat > "$SERVICE_DIR/requirements.txt" << EOF
fastapi==0.104.1
uvicorn==0.24.0
EOF

            cat > "$SERVICE_DIR/$APP_MAIN_FILE" << EOF
# $SERVICE_TYPE service: $SERVICE_NAME
from fastapi import FastAPI
import uvicorn
import os

app = FastAPI(title="$SERVICE_NAME", description="$SERVICE_TYPE service")

@app.get("/")
async def root():
    return {
        "message": "Hello from $SERVICE_NAME!",
        "service": "$SERVICE_NAME",
        "type": "$SERVICE_TYPE",
        "runtime": "$RUNTIME_VARIANT"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "$SERVICE_NAME",
        "type": "$SERVICE_TYPE"
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", $APP_PORT))
    host = os.getenv("HOST", "0.0.0.0")
    uvicorn.run(app, host=host, port=port)
EOF
            ;;
            
        golang)
            cat > "$SERVICE_DIR/go.mod" << EOF
module $SERVICE_NAME

go 1.21
EOF

            cat > "$SERVICE_DIR/main.go" << EOF
// $SERVICE_TYPE service: $SERVICE_NAME
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"
)

type Response struct {
    Message   string \`json:"message"\`
    Service   string \`json:"service"\`
    Type      string \`json:"type"\`
    Runtime   string \`json:"runtime"\`
    Timestamp string \`json:"timestamp,omitempty"\`
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "$APP_PORT"
    }

    http.HandleFunc("/", rootHandler)
    http.HandleFunc("/health", healthHandler)

    fmt.Printf("🚀 $SERVICE_NAME ($SERVICE_TYPE) running on http://0.0.0.0:%s\n", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
    response := Response{
        Message: "Hello from $SERVICE_NAME!",
        Service: "$SERVICE_NAME",
        Type:    "$SERVICE_TYPE",
        Runtime: "$RUNTIME_VARIANT",
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    response := Response{
        Message:   "healthy",
        Service:   "$SERVICE_NAME",
        Type:      "$SERVICE_TYPE",
        Timestamp: time.Now().Format(time.RFC3339),
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}
EOF
            ;;
            
        database)
            # Create database initialization scripts
            mkdir -p "$SERVICE_DIR/init"
            cat > "$SERVICE_DIR/init/01-init.sql" << EOF
-- $SERVICE_TYPE service: $SERVICE_NAME
-- Database: $DB_NAME

CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF

            cat > "$SERVICE_DIR/README.md" << EOF
# $SERVICE_NAME Database Service

## Configuration
- Database Type: $RUNTIME_VARIANT
- Database Name: $DB_NAME
- Database User: $DB_USER
- Port: $APP_PORT

## Connection String
\`\`\`
$RUNTIME_VARIANT://$DB_USER:$DB_PASSWORD@$SERVICE_HOSTNAME.proxmox.local:$APP_PORT/$DB_NAME
\`\`\`

## Management
- Connect: \`psql -h $SERVICE_HOSTNAME.proxmox.local -p $APP_PORT -U $DB_USER -d $DB_NAME\`
- Backup: \`pg_dump -h $SERVICE_HOSTNAME.proxmox.local -p $APP_PORT -U $DB_USER $DB_NAME > backup.sql\`
EOF
            ;;
            
        static)
            mkdir -p "$SERVICE_DIR/public"
            cat > "$SERVICE_DIR/public/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$SERVICE_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 40px; }
        .info { background: #f5f5f5; padding: 20px; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 $SERVICE_NAME</h1>
            <p>Static site service deployed on Proxmox</p>
        </div>
        
        <div class="info">
            <h2>Service Information</h2>
            <ul>
                <li><strong>Service:</strong> $SERVICE_NAME</li>
                <li><strong>Type:</strong> $SERVICE_TYPE</li>
                <li><strong>Runtime:</strong> $RUNTIME_VARIANT</li>
                <li><strong>Port:</strong> $APP_PORT</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
            ;;
        tor-proxy)
            # No app code; configs are handled by deploy template
            ;;
    esac
    
    log_info "✅ Created $SERVICE_TYPE service starter files"
}

# Generate deployment configuration
generate_deployment() {
    log_step "Generating deployment configuration..."
    
    mkdir -p "$DEPLOYMENT_DIR"/{group_vars,templates,scripts}
    
    # Create service configuration
    cat > "$DEPLOYMENT_DIR/service-config.yml" << EOF
# Service configuration for $SERVICE_NAME
# Generated on $(date)

service_name: $SERVICE_NAME
service_type: $SERVICE_TYPE
runtime_variant: $RUNTIME_VARIANT
vm_name: $SERVICE_NAME
vm_id: $VM_ID
vm_cores: $VM_CORES
vm_memory: $VM_MEMORY
vm_disk_size: $VM_DISK_SIZE
vm_storage: local-lvm
vm_network_bridge: vmbr0
vm_swap: 512
vm_unprivileged: true

app_name: $SERVICE_NAME
app_user: $APP_USER
app_dir: /opt/$SERVICE_NAME
app_service_name: $SERVICE_NAME
app_port: $APP_PORT
app_main_file: $APP_MAIN_FILE
local_app_path: "../../services/$SERVICE_NAME"

service_hostname: $SERVICE_HOSTNAME
app_subdomain: $APP_SUBDOMAIN

dns_server: 192.168.1.11
dns_domain: proxmox.local

# Proxmox node override (leave empty to use global default)
proxmox_node: $PROXMOX_NODE

# Service type specific configuration
EOF

    if [[ "$SERVICE_TYPE" == "database" ]]; then
        cat >> "$DEPLOYMENT_DIR/service-config.yml" << EOF
db_type: $RUNTIME_VARIANT
db_name: $DB_NAME
db_user: $DB_USER
db_password: $DB_PASSWORD
EOF
    fi

    if [[ "$SERVICE_TYPE" == "tor-proxy" ]]; then
        cat >> "$DEPLOYMENT_DIR/service-config.yml" << EOF
http_proxy_port: 8118
custom_env_vars:
  TOR_NewCircuitPeriod: 60
  TOR_MaxCircuitDirtiness: 600
EOF
    fi

    if [[ "$SERVICE_TYPE" == "nodejs" ]]; then
        cat >> "$DEPLOYMENT_DIR/service-config.yml" << EOF
nodejs_runtime: $RUNTIME_VARIANT
EOF
    fi

    cat >> "$DEPLOYMENT_DIR/service-config.yml" << EOF

# Custom environment variables
custom_env_vars: {}

# Additional ports to open in firewall
additional_ports: []
EOF

    log_info "✅ Generated service configuration"
}

# Main execution
create_service_starter
generate_deployment

# Use the original generator for now (we'll enhance it later)
log_step "Generating Ansible deployment files..."
if [[ -n "$SERVICE_TYPE" ]]; then
    SERVICE_TYPE_CFG="$SERVICE_TYPE" \
    "$TEMPLATES_BASE/generators/generate-service-deployment.sh" \
        "$SERVICE_NAME" \
        --vm-id "$VM_ID" \
        --port "$APP_PORT" \
        $( [[ -n "$APP_SUBDOMAIN" ]] && printf "%s %q" --subdomain "$APP_SUBDOMAIN" ) \
        --hostname "$SERVICE_HOSTNAME" \
        --cores "$VM_CORES" \
        --memory "$VM_MEMORY" \
        --disk "$VM_DISK_SIZE" \
        --user "$APP_USER" \
        --force
else
    "$TEMPLATES_BASE/generators/generate-service-deployment.sh" \
        "$SERVICE_NAME" \
        --vm-id "$VM_ID" \
        --port "$APP_PORT" \
        $( [[ -n "$APP_SUBDOMAIN" ]] && printf "%s %q" --subdomain "$APP_SUBDOMAIN" ) \
        --hostname "$SERVICE_HOSTNAME" \
        --cores "$VM_CORES" \
        --memory "$VM_MEMORY" \
        --disk "$VM_DISK_SIZE" \
        --user "$APP_USER" \
        --force
fi

echo ""
echo "🎉 Multi-Language Service Generated!"
echo "===================================="
echo ""
echo "📁 Service Type: $SERVICE_TYPE ($RUNTIME_VARIANT)"
echo "📁 Generated files:"
echo "   • services/$SERVICE_NAME/     - Service source code"
echo "   • deployments/$SERVICE_NAME/  - Deployment configuration"
echo ""
echo "🚀 Next steps:"
echo "   1. Customize service code: services/$SERVICE_NAME/"
echo "   2. Deploy service: cd deployments/$SERVICE_NAME && ./deploy.sh"
echo ""
echo "💡 Quick deploy:"
echo "   cd deployments/$SERVICE_NAME && ./deploy.sh"
