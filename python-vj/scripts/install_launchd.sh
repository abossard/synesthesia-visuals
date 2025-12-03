#!/bin/bash
# Install VJ workers as launchd services (macOS)
#
# Usage:
#   ./scripts/install_launchd.sh
#
# This creates launchd plist files for all workers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
USER="$(whoami)"

echo "===== Installing Python-VJ Launchd Services ====="
echo "Project directory: $PROJECT_DIR"
echo "Launchd directory: $LAUNCHD_DIR"
echo "Running as user: $USER"
echo

# Create launchd directory if needed
mkdir -p "$LAUNCHD_DIR"

# Create plist for process manager
echo "Creating launchd services..."

cat > "$LAUNCHD_DIR/com.python-vj.process-manager.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.python-vj.process-manager</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$PROJECT_DIR/workers/process_manager_daemon.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/vj-process-manager.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/vj-process-manager.error.log</string>
</dict>
</plist>
EOF

cat > "$LAUNCHD_DIR/com.python-vj.audio-analyzer.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.python-vj.audio-analyzer</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$PROJECT_DIR/workers/audio_analyzer_worker.py</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/vj-audio-analyzer.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/vj-audio-analyzer.error.log</string>
</dict>
</plist>
EOF

# Load services
echo "Loading services..."
launchctl load "$LAUNCHD_DIR/com.python-vj.process-manager.plist"
launchctl load "$LAUNCHD_DIR/com.python-vj.audio-analyzer.plist"

echo
echo "===== Installation Complete ====="
echo
echo "Services installed:"
echo "  - com.python-vj.process-manager"
echo "  - com.python-vj.audio-analyzer"
echo
echo "Check status:"
echo "  launchctl list | grep python-vj"
echo
echo "View logs:"
echo "  tail -f ~/Library/Logs/vj-process-manager.log"
echo "  tail -f ~/Library/Logs/vj-audio-analyzer.log"
echo
echo "Unload services:"
echo "  launchctl unload ~/Library/LaunchAgents/com.python-vj.*.plist"
echo
