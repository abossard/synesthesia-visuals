#!/bin/bash
# analyze-profile.sh — Post-session profiling analysis for SwiftVJApp
# Usage: ./Scripts/analyze-profile.sh [session-dir]
#
# If no session-dir is given, finds the most recent session in profiling/

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[analyze]${NC} $*"; }
warn() { echo -e "${YELLOW}[analyze]${NC} $*"; }
err()  { echo -e "${RED}[analyze]${NC} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

# Find session directory
if [ -n "${1:-}" ]; then
    SESSION_DIR="$1"
else
    SESSION_DIR=$(ls -dt profiling/session-* 2>/dev/null | head -1)
    if [ -z "$SESSION_DIR" ]; then
        err "No session directories found in profiling/"
        err "Usage: $0 [session-dir]"
        exit 1
    fi
fi

if [ ! -d "$SESSION_DIR" ]; then
    err "Session directory not found: $SESSION_DIR"
    exit 1
fi

REPORT_FILE="${SESSION_DIR}/analysis-report.md"

log "Analyzing session: ${SESSION_DIR}"

# Start report
{
echo "# SwiftVJApp Profiling Report"
echo ""
echo "**Session:** \`$(basename "$SESSION_DIR")\`"
echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --- Session metadata ---
if [ -f "${SESSION_DIR}/session-info.json" ]; then
    header "Session Info"
    echo ""
    echo '```json'
    cat "${SESSION_DIR}/session-info.json"
    echo '```'
    echo ""
fi

# --- xctrace Time Profiler export ---
TRACE_FILE="${SESSION_DIR}/cpu-trace.trace"
if [ -d "$TRACE_FILE" ]; then
    header "CPU Profile (Time Profiler)"
    echo ""

    # Export xctrace data to XML for parsing
    EXPORT_FILE="${SESSION_DIR}/cpu-export.xml"
    if [ ! -f "$EXPORT_FILE" ]; then
        log "Exporting xctrace data (this may take a moment)..."
        xcrun xctrace export --input "$TRACE_FILE" --output "$EXPORT_FILE" 2>/dev/null || {
            warn "xctrace export failed — trace may need to be opened in Instruments manually"
            echo "⚠️ xctrace export failed. Open the trace file directly in Instruments:"
            echo '```'
            echo "open ${TRACE_FILE}"
            echo '```'
            echo ""
        }
    fi

    if [ -f "$EXPORT_FILE" ]; then
        EXPORT_SIZE=$(du -h "$EXPORT_FILE" | cut -f1)
        echo "- **Trace file:** \`$(basename "$TRACE_FILE")\` ($(du -h "$TRACE_FILE" | cut -f1 | xargs))"
        echo "- **Export size:** ${EXPORT_SIZE}"
        echo ""
    fi

    # Extract table of contents from the trace
    log "Extracting trace table of contents..."
    TOC_FILE="${SESSION_DIR}/trace-toc.txt"
    xcrun xctrace export --input "$TRACE_FILE" --toc 2>/dev/null > "$TOC_FILE" || true
    if [ -s "$TOC_FILE" ]; then
        echo "### Available Instruments in Trace"
        echo '```'
        cat "$TOC_FILE"
        echo '```'
        echo ""
    fi

    echo "### How to Investigate"
    echo '```bash'
    echo "open ${TRACE_FILE}"
    echo '```'
    echo ""
    echo "**In Instruments, look for:**"
    echo "1. **Heaviest stack traces** — which functions consume the most CPU?"
    echo "2. **Thread breakdown** — render thread vs MainActor vs cooperative pool"
    echo "3. **Time distribution** — steady-state cost vs track-change spikes"
    echo "4. **MainActor time** — is SwiftUI text rendering a bottleneck?"
    echo ""
else
    echo ""
    echo "⚠️ No cpu-trace.trace found in session directory."
    echo ""
fi

# --- vmmap memory analysis ---
VMMAP_FILES=($(ls "${SESSION_DIR}"/vmmap-*.txt 2>/dev/null || true))
if [ ${#VMMAP_FILES[@]} -gt 0 ]; then
    header "Memory Analysis (vmmap snapshots)"
    echo ""
    echo "| Snapshot | Time | Dirty (MB) | Swapped (MB) | Resident (MB) |"
    echo "|----------|------|------------|-------------|---------------|"

    for vmf in "${VMMAP_FILES[@]}"; do
        fname=$(basename "$vmf")
        # Extract time from filename: vmmap-N-tXXXs.txt
        time_label=$(echo "$fname" | sed -E 's/vmmap-[0-9]+-t([0-9]+)s\.txt/\1s/')
        time_min=$(( $(echo "$time_label" | tr -d 's') / 60 ))

        # Parse vmmap summary for key metrics
        dirty=$(grep -i "^TOTAL" "$vmf" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+[MKG]?$/ || $(i-1) == "Dirty") print $i}' | head -1 || echo "?")
        # Try a more reliable parse
        dirty_kb=$(grep "^TOTAL" "$vmf" 2>/dev/null | awk '{print $5}' || echo "0")
        swapped_kb=$(grep "^TOTAL" "$vmf" 2>/dev/null | awk '{print $7}' || echo "0")
        resident_kb=$(grep "^TOTAL" "$vmf" 2>/dev/null | awk '{print $3}' || echo "0")

        # Convert KB to MB
        dirty_mb=$(echo "scale=1; ${dirty_kb:-0} / 1024" | bc 2>/dev/null || echo "?")
        swapped_mb=$(echo "scale=1; ${swapped_kb:-0} / 1024" | bc 2>/dev/null || echo "?")
        resident_mb=$(echo "scale=1; ${resident_kb:-0} / 1024" | bc 2>/dev/null || echo "?")

        echo "| ${fname} | t+${time_min}m | ${dirty_mb} | ${swapped_mb} | ${resident_mb} |"
    done

    echo ""

    # Memory growth check
    if [ ${#VMMAP_FILES[@]} -ge 2 ]; then
        first_file="${VMMAP_FILES[0]}"
        last_file="${VMMAP_FILES[-1]}"
        first_dirty=$(grep "^TOTAL" "$first_file" 2>/dev/null | awk '{print $5}' || echo "0")
        last_dirty=$(grep "^TOTAL" "$last_file" 2>/dev/null | awk '{print $5}' || echo "0")

        if [ "${first_dirty:-0}" -gt 0 ] && [ "${last_dirty:-0}" -gt 0 ]; then
            growth=$(( (last_dirty - first_dirty) ))
            growth_mb=$(echo "scale=1; ${growth} / 1024" | bc 2>/dev/null || echo "?")
            pct=$(echo "scale=1; ${growth} * 100 / ${first_dirty}" | bc 2>/dev/null || echo "?")
            echo "### Memory Growth"
            echo "- **Start dirty:** $(echo "scale=1; ${first_dirty} / 1024" | bc) MB"
            echo "- **End dirty:** $(echo "scale=1; ${last_dirty} / 1024" | bc) MB"
            echo "- **Growth:** ${growth_mb} MB (${pct}%)"
            echo ""
            if [ "${growth}" -gt 102400 ]; then
                echo "⚠️ **Significant memory growth detected (>100MB).** Investigate Metal texture leaks or growing caches."
            elif [ "${growth}" -gt 0 ]; then
                echo "✅ **Memory growth appears modest.** Normal for long-running sessions with shader/image caching."
            else
                echo "✅ **No memory growth detected.** Memory is stable."
            fi
            echo ""
        fi
    fi

    # Metal/IOKit analysis from vmmap
    echo "### Metal & GPU Memory (from vmmap)"
    echo ""
    for vmf in "${VMMAP_FILES[@]}"; do
        fname=$(basename "$vmf")
        echo "**${fname}:**"
        echo '```'
        grep -E "^(IOKit|Metal|CG |GPU)" "$vmf" 2>/dev/null || echo "(no Metal/IOKit entries)"
        echo '```'
        echo ""
    done
else
    echo ""
    echo "⚠️ No vmmap snapshots found."
    echo ""
fi

# --- sample analysis ---
SAMPLE_FILES=($(ls "${SESSION_DIR}"/sample-*.txt 2>/dev/null || true))
if [ ${#SAMPLE_FILES[@]} -gt 0 ]; then
    header "CPU Samples"
    echo ""
    for sf in "${SAMPLE_FILES[@]}"; do
        fname=$(basename "$sf")
        time_label=$(echo "$fname" | sed -E 's/sample-t([0-9]+m)\.txt/\1/')
        echo "### Sample at t+${time_label}"
        echo ""

        # Extract heaviest stack (top of the "Call graph" section)
        echo "**Heaviest stack trace (top 20 frames):**"
        echo '```'
        # Try to get the heaviest thread/stack
        sed -n '/^Call graph/,/^$/p' "$sf" 2>/dev/null | head -25 || \
            head -40 "$sf" 2>/dev/null || \
            echo "(could not parse sample output)"
        echo '```'
        echo ""

        # Thread summary
        echo "**Thread summary:**"
        echo '```'
        grep -E "^Thread_[0-9]|^  [0-9]+ " "$sf" 2>/dev/null | head -20 || \
            echo "(no thread summary found)"
        echo '```'
        echo ""
    done
else
    echo ""
    echo "ℹ️ No sample snapshots found (session may have been shorter than 10 minutes)."
    echo ""
fi

# --- Summary & recommendations ---
header "Analysis Summary"
echo ""
echo "### Files in this session"
echo '```'
ls -lh "${SESSION_DIR}/" | tail -n +2
echo '```'
echo ""
echo "### Next Steps"
echo "1. **Open the trace in Instruments** for interactive exploration:"
echo '   ```bash'
echo "   open ${SESSION_DIR}/cpu-trace.trace"
echo '   ```'
echo "2. **Look for CPU hotspots** in the Time Profiler instrument"
echo "3. **Compare vmmap snapshots** to identify memory growth patterns"
echo "4. **Check the memory growth section** above for leak indicators"
echo "5. **Correlate sample snapshots** with specific moments in the session"
echo ""

} > "$REPORT_FILE"

log "Report written to: ${REPORT_FILE}"
echo ""
cat "$REPORT_FILE"
