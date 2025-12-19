#!/usr/bin/env bash
set -euo pipefail

IN_PORT=9999
OUT_PORTS=(10000 11111)
DURATION=10
IFACE=""
MODE="both"
PID=""

usage() {
  cat <<'EOF'
Usage: osc_hub_probe.sh [--pid PID] [--duration SECONDS] [--iface IFACE] [--mode latency|load|both]

Measures OSC hub latency (udp 9999 -> 10000/11111) and process load without Python.

Examples:
  ./osc_hub_probe.sh --duration 15
  ./osc_hub_probe.sh --pid 12345 --mode latency
  ./osc_hub_probe.sh --iface lo0 --mode load
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

detect_iface() {
  if [[ -n "$IFACE" ]]; then
    return
  fi
  case "$(uname -s)" in
    Darwin) IFACE="lo0" ;;
    *) IFACE="lo" ;;
  esac
}

find_pid() {
  if [[ -n "$PID" ]]; then
    return
  fi
  require_cmd lsof
  PID=$(lsof -nP -iUDP:${IN_PORT} -sUDP:LISTEN 2>/dev/null | awk 'NR==2{print $2}')
  if [[ -z "$PID" ]]; then
    PID=$(lsof -nP -iUDP:${IN_PORT} 2>/dev/null | awk 'NR==2{print $2}')
  fi
  if [[ -z "$PID" ]]; then
    echo "Could not find a process bound to UDP ${IN_PORT}. Use --pid." >&2
    exit 1
  fi
}

show_load() {
  find_pid
  echo "Process load snapshot:"
  ps -p "$PID" -o pid=,%cpu=,%mem=,rss=,vsz=,etime=,command=
}

measure_latency() {
  detect_iface
  require_cmd tcpdump
  require_cmd awk
  require_cmd sort

  local tmp_capture
  local tmp_deltas
  local tmp_stats
  local tmp_sorted
  tmp_capture=$(mktemp)
  tmp_deltas=$(mktemp)
  tmp_stats=$(mktemp)
  tmp_sorted=$(mktemp)

  cleanup() {
    rm -f "$tmp_capture" "$tmp_deltas" "$tmp_stats" "$tmp_sorted"
  }
  trap cleanup EXIT

  local filter="udp and (port ${IN_PORT} or port ${OUT_PORTS[0]} or port ${OUT_PORTS[1]})"
  local tcpdump_cmd=(tcpdump -i "$IFACE" -tt -n -l -s 0 "$filter")
  if [[ $EUID -ne 0 ]]; then
    tcpdump_cmd=(sudo "${tcpdump_cmd[@]}")
  fi

  echo "Capturing ${DURATION}s on ${IFACE}..."
  "${tcpdump_cmd[@]}" > "$tmp_capture" 2>/dev/null &
  local tcpdump_pid=$!
  sleep "$DURATION"
  kill -INT "$tcpdump_pid" 2>/dev/null || true
  wait "$tcpdump_pid" 2>/dev/null || true

  awk -v in_port="$IN_PORT" -v out_ports="${OUT_PORTS[*]}" -v stats="$tmp_stats" '
    function port_of(addr,    n, parts) {
      gsub(":", "", addr)
      n = split(addr, parts, ".")
      return parts[n]
    }
    BEGIN {
      n = split(out_ports, out_arr, " ")
      for (i = 1; i <= n; i++) out[out_arr[i]] = 1
      out_total = n
    }
    {
      if ($1 !~ /^[0-9]+\.[0-9]+$/) next
      ts = $1
      dst = ""
      for (i = 1; i <= NF; i++) {
        if ($i == ">") {
          dst = $(i + 1)
          break
        }
      }
      if (dst == "") next
      dst_port = port_of(dst)
      if (dst_port == in_port) {
        in_count++
        t_in = ts
        pending = out_total
        next
      }
      if (dst_port in out) {
        out_count++
        if (t_in > 0) {
          delta = ts - t_in
          print delta
          delta_count++
          sum += delta
          if (delta_count == 1 || delta < min) min = delta
          if (delta > max) max = delta
          if (pending > 0) pending--
          if (pending == 0) t_in = 0
        }
      }
    }
    END {
      printf "%d %d %d %.9f %.9f %.9f\n", in_count, out_count, delta_count, sum, min, max > stats
    }
  ' "$tmp_capture" > "$tmp_deltas"

  read -r in_count out_count delta_count sum min max < "$tmp_stats"
  local in_rate out_rate
  in_rate=$(awk -v n="$in_count" -v d="$DURATION" 'BEGIN { if (d>0) printf "%.2f", n/d; else print "0.00"; }')
  out_rate=$(awk -v n="$out_count" -v d="$DURATION" 'BEGIN { if (d>0) printf "%.2f", n/d; else print "0.00"; }')

  echo "Traffic rates: inbound ${in_rate} msg/s, outbound ${out_rate} msg/s"

  if [[ "$delta_count" -eq 0 ]]; then
    echo "No latency samples captured."
    return
  fi

  sort -n "$tmp_deltas" > "$tmp_sorted"
  local p50_idx p95_idx p50 p95 avg
  p50_idx=$(( (delta_count * 50 + 99) / 100 ))
  p95_idx=$(( (delta_count * 95 + 99) / 100 ))
  p50=$(sed -n "${p50_idx}p" "$tmp_sorted")
  p95=$(sed -n "${p95_idx}p" "$tmp_sorted")
  avg=$(awk -v s="$sum" -v c="$delta_count" 'BEGIN { printf "%.9f", s / c }')

  local min_ms max_ms avg_ms p50_ms p95_ms
  min_ms=$(awk -v v="$min" 'BEGIN { printf "%.3f", v * 1000 }')
  max_ms=$(awk -v v="$max" 'BEGIN { printf "%.3f", v * 1000 }')
  avg_ms=$(awk -v v="$avg" 'BEGIN { printf "%.3f", v * 1000 }')
  p50_ms=$(awk -v v="$p50" 'BEGIN { printf "%.3f", v * 1000 }')
  p95_ms=$(awk -v v="$p95" 'BEGIN { printf "%.3f", v * 1000 }')

  echo "Latency (inbound -> outbound):"
  echo "  samples: ${delta_count} (from ${in_count} inbound / ${out_count} outbound)"
  echo "  avg: ${avg_ms} ms, p50: ${p50_ms} ms, p95: ${p95_ms} ms"
  echo "  min: ${min_ms} ms, max: ${max_ms} ms"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid)
      PID="$2"
      shift 2
      ;;
    --duration|-d)
      DURATION="$2"
      shift 2
      ;;
    --iface|-i)
      IFACE="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$MODE" in
  latency)
    measure_latency
    ;;
  load)
    show_load
    ;;
  both)
    show_load
    measure_latency
    ;;
  *)
    echo "Invalid --mode: $MODE (use latency|load|both)" >&2
    exit 1
    ;;
esac
