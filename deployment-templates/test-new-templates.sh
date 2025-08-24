#!/bin/bash

# Test script for new template system
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test service types
SERVICE_TYPES=("nodejs" "database" "python" "tor-proxy")

echo "🧪 Testing new template system..."

for service_type in "${SERVICE_TYPES[@]}"; do
    echo ""
    echo "Testing $service_type service type..."

    # Generate test service
    test_service="test-${service_type}-$(date +%s)"

    if ./generators/generate-service-deployment.sh "$test_service" \
        --port $((3000 + RANDOM % 1000)) \
        --force; then
        echo "✅ $service_type template generation successful"

        # Verify files exist
        deployment_dir="$TEMPLATES_ROOT/deployments/$test_service"
        if [[ -f "$deployment_dir/deploy.yml" && \
              -f "$deployment_dir/scripts/custom_script.sh" ]]; then
            echo "✅ Required files generated"
        else
            echo "❌ Missing required files"
        fi

        # Test syntax
        if ansible-playbook "$deployment_dir/deploy.yml" --syntax-check >/dev/null 2>&1; then
            echo "✅ Ansible syntax valid"
        else
            echo "❌ Ansible syntax invalid"
        fi
    else
        echo "❌ $service_type template generation failed"
    fi
done

echo ""
echo "🎉 Template testing completed"

