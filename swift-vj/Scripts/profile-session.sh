#!/bin/bash
# profile-session.sh — Orchestrates a full profiling session for SwiftVJApp
# Usage: ./Scripts/profile-session.sh [duration_minutes]
#
# Captures:
#   1. xctrace Time Profiler (full session)
#   2. vmmap snapshots every 5 minutes
#   3. sample snapshots at 10-min and 30-min marks
#
# All output goes to profiling/session-YYYYMMDD-HHMMSS/

set -euo pipefail

DURATION_MINS="${1:-40}"
DURATION_SECS=$((DURATION_MINS * 60))
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SESSION_DIR="profiling/session-${TIMESTAMP}"
APP_BINARY=".build/release/SwiftVJApp"
VMMAP_INTERVAL=300  # 5 minutes
SAMPLE_MARKS=(600 1800)  # 10-min and 30-min marks in seconds

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[profile]${NC} $*"; }
warn() { echo -e "${YELLOW}[profile]${NC} $*"; }
err()  { echo -e "${RED}[profile]${NC} $*" >&2; }

# Cleanup on exit
XCTRACE_PID=""
VMMAP_PID=""
SAMPLE_PID=""

cleanup() {
    log "Cleaning up background processes..."
    for pid in $VMMAP_PID $SAMPLE_PID; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    # xctrace stops when the app exits; no need to kill it
    log "Session data saved to: ${SESSION_DIR}/"
    echo ""
    log "=== Post-Session ==="
    log "To analyze: make analyze-session"
    log "Or open trace directly: open ${SESSION_DIR}/cpu-trace.trace"
}
trap cleanup EXIT

# Preflight checks
if [ ! -f "$APP_BINARY" ]; then
    err "Release binary not found. Run: make profile-build"
    exit 1
fi

if ! command -v xctrace &>/dev/null; then
    err "xctrace not found. Install Xcode command line tools."
    exit 1
fi

# Create session directory
mkdir -p "${SESSION_DIR}"

log "=== SwiftVJApp Profiling Session ==="
log "Duration:   ${DURATION_MINS} minutes"
log "Output:     ${SESSION_DIR}/"
log "Captures:   Time Profiler + vmmap (every 5m) + sample (at 10m, 30m)"
echo ""

# Save session metadata
cat > "${SESSION_DIR}/session-info.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "duration_minutes": ${DURATION_MINS},
  "binary": "${APP_BINARY}",
  "hostname": "$(hostname)",
  "os_version": "$(sw_vers -productVersion)",
  "chip": "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')",
  "memory_gb": $(( $(sysctl -n hw.memsize) / 1073741824 )),
  "synesthesia_running": false,
  "notes": "No Synesthesia — baseline rendering profile with VDJ playback"
}
EOF

# --- 1. Start xctrace Time Profiler ---
log "Starting Time Profiler (xctrace)..."
xcrun xctrace record \
    --template "Time Profiler" \
    --output "${SESSION_DIR}/cpu-trace.trace" \
    --launch "$APP_BINARY" &
XCTRACE_PID=$!

# Wait for the app to start
sleep 3

# Find the SwiftVJApp PID (launched by xctrace)
APP_PID=$(pgrep -x SwiftVJApp 2>/dev/null || true)
if [ -z "$APP_PID" ]; then
    sleep 2
    APP_PID=$(pgrep -x SwiftVJApp 2>/dev/null || true)
fi

if [ -z "$APP_PID" ]; then
    warn "Could not find SwiftVJApp PID. vmmap/sample snapshots will be skipped."
    warn "Time Profiler is still recording — quit the app when done."
    wait $XCTRACE_PID 2>/dev/null || true
    exit 0
fi

log "SwiftVJApp running (PID: ${APP_PID})"
echo "${APP_PID}" > "${SESSION_DIR}/app.pid"

# --- 2. Background vmmap snapshots ---
(
    elapsed=0
    snapshot=0
    while kill -0 "$APP_PID" 2>/dev/null; do
        if [ $((elapsed % VMMAP_INTERVAL)) -eq 0 ]; then
            snap_file="${SESSION_DIR}/vmmap-${snapshot}-t${elapsed}s.txt"
            vmmap --summary "$APP_PID" > "$snap_file" 2>/dev/null && \
                log "vmmap snapshot #${snapshot} (t+${elapsed}s) saved" || true
            snapshot=$((snapshot + 1))
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
) &
VMMAP_PID=$!

# --- 3. Background sample snapshots at specific marks ---
(
    START_TIME=$(date +%s)
    for mark_sec in "${SAMPLE_MARKS[@]}"; do
        mark_min=$((mark_sec / 60))
        # Wait until the mark
        while true; do
            NOW=$(date +%s)
            ELAPSED=$((NOW - START_TIME))
            if [ "$ELAPSED" -ge "$mark_sec" ]; then
                break
            fi
            # Check if app is still running
            if ! kill -0 "$APP_PID" 2>/dev/null; then
                exit 0
            fi
            sleep 5
        done
        # Take sample (5 seconds of sampling)
        if kill -0 "$APP_PID" 2>/dev/null; then
            sample_file="${SESSION_DIR}/sample-t${mark_min}m.txt"
            log "Taking CPU sample at t+${mark_min}m..."
            sample "$APP_PID" 5 -file "$sample_file" 2>/dev/null && \
                log "sample at t+${mark_min}m saved" || \
                warn "sample at t+${mark_min}m failed (app may have exited)"
        fi
    done
) &
SAMPLE_PID=$!

# --- Wait for xctrace / app to finish ---
echo ""
log "Profiling active. Play music in VDJ!"
log "Quit SwiftVJApp (⌘Q) when the session is done."
echo ""

wait $XCTRACE_PID 2>/dev/null || true

log "xctrace recording complete."
