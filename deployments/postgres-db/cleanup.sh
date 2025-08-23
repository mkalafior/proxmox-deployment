#!/bin/bash

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="$(basename "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🧹 Cleanup $SERVICE_NAME Deployment"
echo "===================================="

if [[ -f "$HOME/.pxdcli/env.global" ]]; then
  source "$HOME/.pxdcli/env.global"
fi
if [[ -f ./env.service ]]; then
  source ./env.service
fi

if [[ ! -f ./group_vars/all.yml ]]; then
  err "group_vars/all.yml missing"
  exit 1
fi

ANSIBLE_CONFIG=${ANSIBLE_CONFIG:-./ansible.cfg}
ANSIBLE_STDOUT_CALLBACK=unixy ansible-playbook cleanup.yml -e @group_vars/all.yml
info "Cleanup playbook completed"
