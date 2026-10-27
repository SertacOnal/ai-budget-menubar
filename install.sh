#!/bin/bash
# AI Budget Menubar - Installation Script

set -e

echo "🔧 AI Budget Menubar Installer"
echo "==============================="
echo

# Check for dependencies
echo "Checking dependencies..."

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found"
    echo "Installing jq via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install jq
    else
        echo "Please install jq: brew install jq"
        exit 1
    fi
else
    echo "✅ jq installed"
fi

if ! command -v bc &> /dev/null; then
    echo "⚠️  bc not found (optional, for calculations)"
fi

# Check for SwiftBar or xbar
PLUGIN_DIR=""
if [[ -d "$HOME/Library/Application Support/SwiftBar/Plugins" ]]; then
    PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
    echo "✅ SwiftBar detected"
elif [[ -d "$HOME/Library/Application Support/xbar/plugins" ]]; then
    PLUGIN_DIR="$HOME/Library/Application Support/xbar/plugins"
    echo "✅ xbar detected"
else
    echo "❌ Neither SwiftBar nor xbar found"
    echo
    echo "Please install SwiftBar (recommended):"
    echo "  brew install --cask swiftbar"
    echo
    echo "Or xbar:"
    echo "  brew install --cask xbar"
    echo
    read -p "Install SwiftBar now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        brew install --cask swiftbar
        PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
        mkdir -p "$PLUGIN_DIR"
    else
        exit 1
    fi
fi

# Create config directory
CONFIG_DIR="$HOME/.config/ai-budget"
mkdir -p "$CONFIG_DIR"

# Install plugin
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PATH="$PLUGIN_DIR/ai-budget.5m.sh"

echo
echo "Installing plugin to: $PLUGIN_PATH"
cp "$SCRIPT_DIR/ai-budget.5m.sh" "$PLUGIN_PATH"
chmod +x "$PLUGIN_PATH"

# Configure API keys
echo
echo "📝 API Key Configuration"
echo "========================"
echo

CONFIG_FILE="$CONFIG_DIR/config"

# Anthropic
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    echo "Using ANTHROPIC_API_KEY from environment"
    ANTHROPIC_KEY="$ANTHROPIC_API_KEY"
else
    read -p "Anthropic API Key (or press Enter to skip): " ANTHROPIC_KEY
fi

# OpenAI
if [[ -n "$OPENAI_API_KEY" ]]; then
    echo "Using OPENAI_API_KEY from environment"
    OPENAI_KEY="$OPENAI_API_KEY"
else
    read -p "OpenAI API Key (or press Enter to skip): " OPENAI_KEY
fi

# Save config
cat > "$CONFIG_FILE" << EOF
# AI Budget Monitor Configuration
# API keys are stored here - keep this file secure

ANTHROPIC_KEY="$ANTHROPIC_KEY"
OPENAI_KEY="$OPENAI_KEY"
EOF
chmod 600 "$CONFIG_FILE"

echo
echo "✅ Installation complete!"
echo
echo "Configuration saved to: $CONFIG_FILE"
echo "Plugin installed to: $PLUGIN_PATH"
echo
echo "Next steps:"
echo "1. Open SwiftBar/xbar from Applications"
echo "2. The 💰 icon should appear in your menubar"
echo "3. Click it to see your budget status"
echo
echo "To update API keys later, edit: $CONFIG_FILE"
