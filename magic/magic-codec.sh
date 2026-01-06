#!/bin/bash
# Magic Music Visuals file encoder/decoder
# Format: 3-byte header (\x16Xr) + zlib-compressed XML

set -e

usage() {
    echo "Usage: $0 <decode|encode> <input_file> [output_file]"
    echo ""
    echo "Commands:"
    echo "  decode <file.magic>  - Decode .magic file to XML"
    echo "  encode <file.xml>    - Encode XML file to .magic format"
    echo ""
    echo "If output_file is not specified:"
    echo "  decode: creates <input>.decoded.xml"
    echo "  encode: creates <input>.magic (with timestamp if exists)"
    echo ""
    echo "NOTE: This script will NEVER overwrite existing .magic files."
    exit 1
}

decode_magic() {
    local input="$1"
    local output="$2"

    if [[ ! -f "$input" ]]; then
        echo "Error: Input file '$input' not found"
        exit 1
    fi

    if [[ -z "$output" ]]; then
        output="${input}.decoded.xml"
    fi

    echo "Decoding: $input -> $output"

    python3 << EOF
import sys
import zlib

with open("$input", "rb") as f:
    data = f.read()

# Skip 3-byte header (\x16Xr)
if len(data) < 4:
    print("Error: File too small to be a valid .magic file", file=sys.stderr)
    sys.exit(1)

header = data[:3]
if header != b'\x16Xr':
    print(f"Warning: Unexpected header {header.hex()}, expected 165872", file=sys.stderr)

compressed = data[3:]

try:
    decompressed = zlib.decompress(compressed)
    with open("$output", "wb") as f:
        f.write(decompressed)
    print(f"Successfully decoded {len(data)} bytes -> {len(decompressed)} bytes")
except zlib.error as e:
    print(f"Error: Failed to decompress: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

encode_magic() {
    local input="$1"
    local output="$2"

    if [[ ! -f "$input" ]]; then
        echo "Error: Input file '$input' not found"
        exit 1
    fi

    if [[ -z "$output" ]]; then
        # Generate output filename from input
        output="${input%.xml}.magic"
        output="${output%.decoded.magic}.magic"
    fi

    # NEVER overwrite existing .magic files - add timestamp if exists
    if [[ -f "$output" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local base="${output%.magic}"
        output="${base}_${timestamp}.magic"
        echo "Warning: Output file exists, using: $output"
    fi

    echo "Encoding: $input -> $output"

    python3 << EOF
import sys
import zlib

HEADER = b'\x16Xr'

with open("$input", "rb") as f:
    data = f.read()

# Compress with zlib (default compression level)
compressed = zlib.compress(data)

# Write header + compressed data
with open("$output", "wb") as f:
    f.write(HEADER)
    f.write(compressed)

print(f"Successfully encoded {len(data)} bytes -> {len(HEADER) + len(compressed)} bytes")
EOF
}

# Main
if [[ $# -lt 2 ]]; then
    usage
fi

command="$1"
input_file="$2"
output_file="${3:-}"

case "$command" in
    decode)
        decode_magic "$input_file" "$output_file"
        ;;
    encode)
        encode_magic "$input_file" "$output_file"
        ;;
    *)
        echo "Error: Unknown command '$command'"
        usage
        ;;
esac
