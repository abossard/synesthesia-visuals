#!/bin/bash
# VJ Console Startup Script
# Easy one-command startup for the entire VJ system

echo "=================================="
echo "🎛️  VJ Console Startup"
echo "=================================="
echo ""
echo "Starting VJ Console with auto-healing workers..."
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change to the script directory
cd "$SCRIPT_DIR"

# Check if virtual environment exists
if [ -d "../.venv" ]; then
    echo "✓ Activating virtual environment..."
    source ../.venv/bin/activate
elif [ -d ".venv" ]; then
    echo "✓ Activating virtual environment..."
    source .venv/bin/activate
else
    echo "⚠️  No virtual environment found. Using system Python."
fi

# Check if dependencies are installed
echo "✓ Checking dependencies..."
python3 -c "import textual" 2>/dev/null || {
    echo "❌ Missing dependencies. Installing..."
    pip install -r requirements.txt
}

echo ""
echo "🚀 Launching VJ Console..."
echo "   - Workers will auto-start automatically"
echo "   - Auto-healing is enabled (crashed workers will restart)"
echo "   - Press 0-5 to switch between screens"
echo "   - Press 'q' to quit"
echo ""
echo "=================================="
echo ""

# Start the console
python3 vj_console.py

echo ""
echo "=================================="
echo "✓ VJ Console stopped"
echo "=================================="
