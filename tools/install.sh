#!/bin/bash
# Unified installation script for pxdcli
# Installs global templates, CLI tool, and bash completion

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
TARGET_DIR="${1:-$HOME/.proxmox-deploy/templates}"
BIN_DIR="${2:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLETION_SCRIPT="$SCRIPT_DIR/pxdcli-completion.bash"

print_header() {
    echo -e "${BOLD}${BLUE}$1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "${BOLD}${GREEN}🔄 $1${NC}"
}

# Parse command line arguments
INSTALL_COMPLETION=true
INSTALL_TEMPLATES=true
FORCE_REINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-completion)
            INSTALL_COMPLETION=false
            shift
            ;;
        --no-templates)
            INSTALL_TEMPLATES=false
            shift
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        --help|-h)
            echo "pxdcli Installation Script"
            echo ""
            echo "Usage: $0 [OPTIONS] [TEMPLATES_DIR] [BIN_DIR]"
            echo ""
            echo "Options:"
            echo "  --no-completion    Skip bash completion installation"
            echo "  --no-templates     Skip global templates installation"
            echo "  --force           Force reinstallation"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "Arguments:"
            echo "  TEMPLATES_DIR     Directory for global templates (default: ~/.proxmox-deploy/templates)"
            echo "  BIN_DIR          Directory for CLI binary (default: ~/.local/bin)"
            echo ""
            echo "Examples:"
            echo "  $0                           # Full installation with defaults"
            echo "  $0 --no-completion          # Install only templates and CLI"
            echo "  $0 --force                  # Force reinstall everything"
            echo "  $0 /opt/pxdcli /usr/local/bin  # Custom directories"
            exit 0
            ;;
        *)
            # Assume it's a directory argument
            if [[ -z "${TARGET_DIR_SET:-}" ]]; then
                TARGET_DIR="$1"
                TARGET_DIR_SET=true
            elif [[ -z "${BIN_DIR_SET:-}" ]]; then
                BIN_DIR="$1"
                BIN_DIR_SET=true
            else
                print_error "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Main installation header
echo ""
print_header "🚀 pxdcli Installation Script"
echo ""
print_info "This script will install:"
if [[ "$INSTALL_TEMPLATES" == "true" ]]; then
    echo "  • Global templates and CLI tool"
fi
if [[ "$INSTALL_COMPLETION" == "true" ]]; then
    echo "  • Bash completion for enhanced productivity"
fi
echo ""

# Step 1: Install Global Templates and CLI
if [[ "$INSTALL_TEMPLATES" == "true" ]]; then
    print_step "Step 1: Installing Global Templates and CLI"
    echo ""
    
    mkdir -p "$TARGET_DIR" "$BIN_DIR"
    
    if [[ ! -d "$TARGET_DIR/.git" || "$FORCE_REINSTALL" == "true" ]]; then
        if [[ -d "$TARGET_DIR/.git" ]]; then
            print_info "Force reinstall requested, removing existing templates..."
            rm -rf "$TARGET_DIR"
            mkdir -p "$TARGET_DIR"
        fi
        
        print_info "Cloning templates to $TARGET_DIR..."
        git clone --depth 1 "$(cd "$SCRIPT_DIR/.." && pwd)" "$TARGET_DIR"
    else
        print_info "Templates already installed at $TARGET_DIR"
        print_info "Updating templates..."
        git -C "$TARGET_DIR" pull --ff-only || {
            print_warning "Failed to update templates (possibly due to local changes)"
            print_info "Use --force to reinstall from scratch"
        }
    fi
    
    # Log repository status
    echo ""
    print_info "Repository Status:"
    echo "  Branch: $(git -C "$TARGET_DIR" rev-parse --abbrev-ref HEAD)"
    echo "  Latest Commit: $(git -C "$TARGET_DIR" log -1 --oneline)"
    echo ""
    
    # Install CLI
    SRC_CLI="$SCRIPT_DIR/proxmox-deploy"
    DEST_CLI="$BIN_DIR/pxdcli"
    
    print_info "Installing CLI tool..."
    chmod +x "$SRC_CLI"
    ln -sf "$SRC_CLI" "$DEST_CLI"
    print_success "CLI installed: $DEST_CLI"
    
    # Check PATH
    if ! echo "$PATH" | grep -q "$BIN_DIR"; then
        print_warning "Add $BIN_DIR to your PATH:"
        if [[ "$SHELL" == *"zsh"* ]]; then
            echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
        else
            echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
        fi
    fi
    
    echo ""
else
    print_info "Skipping templates installation (--no-templates specified)"
    echo ""
fi

# Step 2: Install Bash Completion
if [[ "$INSTALL_COMPLETION" == "true" ]]; then
    print_step "Step 2: Installing Bash Completion"
    echo ""
    
    # Check if completion script exists
    if [[ ! -f "$COMPLETION_SCRIPT" ]]; then
        print_error "Completion script not found at: $COMPLETION_SCRIPT"
        exit 1
    fi
    
    # Determine the appropriate completion directory
    COMPLETION_DIR=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew >/dev/null 2>&1; then
            # Homebrew bash-completion
            BREW_PREFIX="$(brew --prefix)"
            if [[ -d "$BREW_PREFIX/etc/bash_completion.d" ]]; then
                COMPLETION_DIR="$BREW_PREFIX/etc/bash_completion.d"
            elif [[ -d "$BREW_PREFIX/share/bash-completion/completions" ]]; then
                COMPLETION_DIR="$BREW_PREFIX/share/bash-completion/completions"
            fi
        fi
        
        # Fallback to user directory
        if [[ -z "$COMPLETION_DIR" ]]; then
            COMPLETION_DIR="$HOME/.bash_completion.d"
            mkdir -p "$COMPLETION_DIR"
        fi
    else
        # Linux
        if [[ -d "/etc/bash_completion.d" ]]; then
            COMPLETION_DIR="/etc/bash_completion.d"
        elif [[ -d "/usr/local/etc/bash_completion.d" ]]; then
            COMPLETION_DIR="/usr/local/etc/bash_completion.d"
        elif [[ -d "/usr/share/bash-completion/completions" ]]; then
            COMPLETION_DIR="/usr/share/bash-completion/completions"
        else
            # Fallback to user directory
            COMPLETION_DIR="$HOME/.bash_completion.d"
            mkdir -p "$COMPLETION_DIR"
        fi
    fi
    
    print_info "Using completion directory: $COMPLETION_DIR"
    
    # Check if we need sudo for system directories
    NEED_SUDO=false
    if [[ "$COMPLETION_DIR" == /etc/* || "$COMPLETION_DIR" == /usr/* ]]; then
        if [[ $EUID -ne 0 ]]; then
            NEED_SUDO=true
            print_warning "System directory requires sudo privileges"
        fi
    fi
    
    # Install the completion script
    TARGET_FILE="$COMPLETION_DIR/pxdcli"
    if [[ "$NEED_SUDO" == "true" ]]; then
        print_info "Installing completion script (requires sudo)..."
        sudo cp "$COMPLETION_SCRIPT" "$TARGET_FILE"
        sudo chmod 644 "$TARGET_FILE"
    else
        print_info "Installing completion script..."
        cp "$COMPLETION_SCRIPT" "$TARGET_FILE"
        chmod 644 "$TARGET_FILE"
    fi
    
    print_success "Completion script installed: $TARGET_FILE"
    
    # Check if bash-completion is available
    if ! command -v complete >/dev/null 2>&1; then
        print_warning "bash-completion not found. You may need to install it:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install bash-completion"
        else
            echo "  # Ubuntu/Debian: sudo apt-get install bash-completion"
            echo "  # CentOS/RHEL: sudo yum install bash-completion"
            echo "  # Fedora: sudo dnf install bash-completion"
        fi
    fi
    
    # Add sourcing to shell profile if needed (for user-local installations)
    if [[ "$COMPLETION_DIR" == "$HOME"* ]]; then
        SHELL_PROFILE=""
        if [[ "$SHELL" == *"zsh"* ]]; then
            SHELL_PROFILE="$HOME/.zshrc"
        elif [[ -n "${BASH_VERSION:-}" ]]; then
            if [[ -f "$HOME/.bashrc" ]]; then
                SHELL_PROFILE="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                SHELL_PROFILE="$HOME/.bash_profile"
            fi
        fi
        
        if [[ -n "$SHELL_PROFILE" ]]; then
            SOURCE_LINE="# Source pxdcli completion"
            SOURCE_CMD="[[ -f \"$TARGET_FILE\" ]] && source \"$TARGET_FILE\""
            
            if ! grep -q "pxdcli-completion\|pxdcli.*completion" "$SHELL_PROFILE" 2>/dev/null; then
                print_info "Adding completion sourcing to $SHELL_PROFILE"
                echo "" >> "$SHELL_PROFILE"
                echo "$SOURCE_LINE" >> "$SHELL_PROFILE"
                echo "$SOURCE_CMD" >> "$SHELL_PROFILE"
                print_success "Added sourcing to shell profile"
            else
                print_info "Completion sourcing already present in shell profile"
            fi
        fi
    fi
    
    echo ""
else
    print_info "Skipping bash completion installation (--no-completion specified)"
    echo ""
fi

# Final success message
print_header "🎉 Installation Complete!"
echo ""

if [[ "$INSTALL_TEMPLATES" == "true" ]]; then
    print_success "Global templates and CLI installed successfully"
    echo "  Templates: $TARGET_DIR"
    echo "  CLI: $DEST_CLI"
fi

if [[ "$INSTALL_COMPLETION" == "true" ]]; then
    print_success "Bash completion installed successfully"
    echo "  Completion: $TARGET_FILE"
fi

echo ""
print_info "Quick Start:"
echo "  pxdcli help                    # Show available commands"
echo "  pxdcli generate my-service     # Create a new service"

if [[ "$INSTALL_COMPLETION" == "true" ]]; then
    echo ""
    print_info "Completion Usage (after restarting shell or sourcing profile):"
    echo "  pxdcli de<TAB>                 # Completes to 'deploy'"
    echo "  pxdcli deploy <TAB>            # Shows available services"
    echo "  pxdcli generate myapp --type <TAB>  # Shows service types"
    
    echo ""
    print_info "To use completion immediately:"
    echo "  source \"$TARGET_FILE\""
fi

# Final checks and warnings
echo ""
if [[ "$INSTALL_TEMPLATES" == "true" ]]; then
    if ! command -v pxdcli >/dev/null 2>&1; then
        print_warning "pxdcli not found in PATH. You may need to:"
        echo "  1. Restart your shell, or"
        echo "  2. Add $BIN_DIR to your PATH manually"
    else
        print_success "pxdcli is ready to use!"
    fi
fi

echo ""
print_info "For help and documentation, visit:"
echo "  https://github.com/your-org/proxmox-deploy-playground"
