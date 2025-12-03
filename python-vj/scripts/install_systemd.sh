#!/bin/bash
# Install VJ workers as systemd services (Linux)
#
# Usage:
#   sudo ./scripts/install_systemd.sh
#
# This creates systemd service files for all workers and enables auto-start

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="/opt/python-vj"
SERVICE_DIR="/etc/systemd/system"
USER="$(logname)"

echo "===== Installing Python-VJ Systemd Services ====="
echo "Project directory: $PROJECT_DIR"
echo "Install directory: $INSTALL_DIR"
echo "Running as user: $USER"
echo

# Copy project to install location
echo "Copying project files..."
mkdir -p "$INSTALL_DIR"
cp -r "$PROJECT_DIR"/* "$INSTALL_DIR/"

# Create virtual environment
echo "Creating virtual environment..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Create systemd service for process manager
echo "Creating systemd services..."

cat > "$SERVICE_DIR/vj-process-manager.service" <<EOF
[Unit]
Description=VJ Process Manager Daemon
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin"
ExecStart=$INSTALL_DIR/venv/bin/python workers/process_manager_daemon.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create service for audio analyzer
cat > "$SERVICE_DIR/vj-audio-analyzer.service" <<EOF
[Unit]
Description=VJ Audio Analyzer Worker
After=network.target vj-process-manager.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin"
ExecStart=$INSTALL_DIR/venv/bin/python workers/audio_analyzer_worker.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo "Reloading systemd..."
systemctl daemon-reload

# Enable services
echo "Enabling services..."
systemctl enable vj-process-manager.service
systemctl enable vj-audio-analyzer.service

# Start services
echo "Starting services..."
systemctl start vj-process-manager.service
systemctl start vj-audio-analyzer.service

echo
echo "===== Installation Complete ====="
echo
echo "Services installed:"
echo "  - vj-process-manager.service"
echo "  - vj-audio-analyzer.service"
echo
echo "Check status:"
echo "  sudo systemctl status vj-process-manager"
echo "  sudo systemctl status vj-audio-analyzer"
echo
echo "View logs:"
echo "  sudo journalctl -u vj-process-manager -f"
echo "  sudo journalctl -u vj-audio-analyzer -f"
echo
