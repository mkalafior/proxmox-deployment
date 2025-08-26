#!/bin/bash

# Template Update Wrapper Script
# Convenient wrapper for the template update system

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "🔄 Template Update System"
echo "========================="
echo ""

# Check if we're in the right directory
if [[ ! -d "deployment-templates" ]]; then
    echo "❌ Please run this script from the project root directory"
    exit 1
fi

# Show current template version
if [[ -f "deployment-templates/.template-version" ]]; then
    echo "📋 Current Template Version:"
    grep "TEMPLATE_VERSION\|LAST_UPDATED" deployment-templates/.template-version | sed 's/^/   /'
    echo ""
fi

# Run the update system
log_step "Running template update system..."
exec deployment-templates/update-deployments.sh "$@"
