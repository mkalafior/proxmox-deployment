#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Inputs (with sensible defaults)
PROXMOX_HOST="${PROXMOX_HOST:-}"
TOKEN_ID="${TOKEN_ID:-}"
TOKEN_SECRET="${TOKEN_SECRET:-}"
NODE="${1:-pve}"
VMID="${2:-996}"
ROOTFS_STORAGE="${3:-local-lvm}"
DISK_GB="${4:-8}"
BRIDGE="${5:-vmbr0}"
OSTEMPLATE_VOLID="${6:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"

if [[ -z "$PROXMOX_HOST" || -z "$TOKEN_ID" || -z "$TOKEN_SECRET" ]]; then
  log_error "Missing PROXMOX_HOST/TOKEN_ID/TOKEN_SECRET env vars"
  echo "export PROXMOX_HOST='192.168.1.99'"
  echo "export TOKEN_ID='root@pam!deploy-root'"
  echo "export TOKEN_SECRET='<secret>'"
  exit 1
fi

AUTH_HEADER="Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}"

log_step "1) Check nodes"
NODES_JSON=$(curl -ks -H "$AUTH_HEADER" "https://${PROXMOX_HOST}:8006/api2/json/nodes")
echo "$NODES_JSON" | python3 -m json.tool 2>/dev/null || echo "$NODES_JSON"
if echo "$NODES_JSON" | grep -q '"node"\s*:\s*"'"$NODE"'"'; then
  log_info "Node exists: $NODE"
else
  log_error "Node not found: $NODE"
  exit 1
fi

log_step "2) Check OS templates on node=$NODE storage=local (vztmpl)"
TMPL_JSON=$(curl -ks -H "$AUTH_HEADER" "https://${PROXMOX_HOST}:8006/api2/json/nodes/${NODE}/storage/local/content?content=vztmpl")
echo "$TMPL_JSON" | python3 -m json.tool 2>/dev/null || echo "$TMPL_JSON"
if echo "$TMPL_JSON" | grep -q '"volid"\s*:\s*"'"$OSTEMPLATE_VOLID"'"'; then
  log_info "Template exists: $OSTEMPLATE_VOLID"
else
  log_warn "Template NOT found in listing: $OSTEMPLATE_VOLID"
fi

log_step "3) Check storage '${ROOTFS_STORAGE}' on node=${NODE}"
STOR_JSON=$(curl -ks -H "$AUTH_HEADER" "https://${PROXMOX_HOST}:8006/api2/json/nodes/${NODE}/storage")
echo "$STOR_JSON" | python3 -m json.tool 2>/dev/null || echo "$STOR_JSON"
if echo "$STOR_JSON" | grep -q '"storage"\s*:\s*"'"$ROOTFS_STORAGE"'"'; then
  log_info "Storage exists: $ROOTFS_STORAGE"
else
  log_error "Storage not found: $ROOTFS_STORAGE"
  exit 1
fi

log_step "4) Test LXC create with parameters (dry test VMID=$VMID)"
TEST_PASS=$(openssl rand -base64 12)

# Encode fields as used in playbook
ENC_OSTEMPLATE=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('${OSTEMPLATE_VOLID}', safe=''))
PY
)
ENC_ROOTFS=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('${ROOTFS_STORAGE}:${DISK_GB}', safe=''))
PY
)
ENC_NET0=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('name=eth0,bridge=${BRIDGE},firewall=1,ip=dhcp', safe=''))
PY
)

POST_DATA="vmid=${VMID}&unprivileged=1&features=nesting%3D1&password=${TEST_PASS}&ostemplate=${ENC_OSTEMPLATE}&rootfs=${ENC_ROOTFS}&cores=1&memory=512&swap=256&net0=${ENC_NET0}"

echo "POST data:"; echo "$POST_DATA"

CREATE_JSON=$(curl -ks -X POST -H "$AUTH_HEADER" -H "Content-Type: application/x-www-form-urlencoded" \
  -d "$POST_DATA" \
  "https://${PROXMOX_HOST}:8006/api2/json/nodes/${NODE}/lxc")
echo "Create response:"; echo "$CREATE_JSON"

if echo "$CREATE_JSON" | grep -q '"UPID'; then
  log_info "Create accepted; cleaning up test VMID ${VMID}"
  curl -ks -X DELETE -H "$AUTH_HEADER" "https://${PROXMOX_HOST}:8006/api2/json/nodes/${NODE}/lxc/${VMID}" >/dev/null || true
elif echo "$CREATE_JSON" | grep -q 'data":null'; then
  log_warn "Create returned data=null (server accepted but no UPID returned)"
else
  log_error "Create appears to have failed"
fi

log_step "Done. If create shows data=null, parameters are still valid; the issue is likely DHCP/bridge."


