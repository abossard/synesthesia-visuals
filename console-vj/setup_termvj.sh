#!/bin/bash
# TERMVJ — Install system dependencies (macOS)
# These are needed before `uv run python termvj.py` can work.

set -e

if ! command -v brew &> /dev/null; then
    echo "⚠  Homebrew not found. Install from https://brew.sh"
    exit 1
fi

echo "→ Installing portaudio (required by pyaudio)..."
brew install portaudio

echo "→ Installing uv (Python package manager)..."
brew install uv

echo "→ Syncing Python dependencies..."
cd "$(dirname "$0")"
uv sync

echo ""
echo "✅ Done! Now run:  uv run python termvj.py"
