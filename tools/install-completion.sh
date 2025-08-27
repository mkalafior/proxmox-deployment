#!/bin/bash
# Install pxdcli completion for the current user

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETION_FILE="$SCRIPT_DIR/pxdcli-completion.bash"

# Detect shell
if [[ -n "${ZSH_VERSION:-}" ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [[ -n "${BASH_VERSION:-}" ]]; then
    if [[ -f "$HOME/.bashrc" ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    else
        SHELL_CONFIG="$HOME/.bash_profile"
    fi
    SHELL_NAME="bash"
else
    echo "❌ Unsupported shell. Please manually source the completion file."
    exit 1
fi

echo "🔧 Installing pxdcli completion for $SHELL_NAME..."

# Check if already installed
if grep -q "pxdcli-completion.bash" "$SHELL_CONFIG" 2>/dev/null; then
    echo "✅ pxdcli completion is already installed in $SHELL_CONFIG"
else
    echo "" >> "$SHELL_CONFIG"
    echo "# pxdcli completion" >> "$SHELL_CONFIG"
    echo "source \"$COMPLETION_FILE\"" >> "$SHELL_CONFIG"
    echo "✅ Added pxdcli completion to $SHELL_CONFIG"
fi

# Source in current shell
if [[ -f "$COMPLETION_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$COMPLETION_FILE"
    echo "✅ Completion loaded in current shell"
else
    echo "❌ Completion file not found: $COMPLETION_FILE"
    exit 1
fi

echo ""
echo "🎉 pxdcli completion installed successfully!"
echo ""
echo "Usage:"
echo "  - Type 'pxdcli ' and press TAB to see available commands"
echo "  - Type 'pxdcli deploy ' and press TAB to see available services"
echo "  - Restart your terminal or run 'source $SHELL_CONFIG' to enable in new shells"
