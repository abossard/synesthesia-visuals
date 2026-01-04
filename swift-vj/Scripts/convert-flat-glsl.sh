#!/bin/bash
# Convert flat GLSL shaders to Metal via SPIR-V
# Usage: convert-flat-glsl.sh <input.txt> <output.metal>

set -e

INPUT="$1"
OUTPUT="$2"
BASENAME=$(basename "$INPUT" .txt)
TEMP_DIR=$(mktemp -d)

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 <input.glsl> <output.metal>"
    exit 1
fi

# Create wrapped GLSL with proper version and structure
WRAPPED="$TEMP_DIR/wrapped.frag"

cat > "$WRAPPED" << 'EOF'
#version 450

layout(binding = 0) uniform Uniforms {
    float time;
    vec2 resolution;
    vec2 mouse;
    float speed;
    float bass;
    float lowMid;
    float mid;
    float highs;
    float level;
    float kickEnv;
    float kickPulse;
    float beat;
    float energyFast;
    float energySlow;
} u;

layout(binding = 1) uniform sampler2D bb;

layout(location = 0) out vec4 fragColor;

// GLSL compatibility - remap old uniforms to block members
#define time u.time
#define resolution u.resolution
#define mouse u.mouse

// texture2D -> texture for GLSL 4.5
#define texture2D texture

EOF

# Extract the main function body from the original shader
# Strip the uniform declarations and GL_ES precision stuff
sed -e '/^#ifdef GL_ES/,/^#endif/d' \
    -e '/^uniform /d' \
    -e '/^precision /d' \
    -e 's/gl_FragColor/fragColor/g' \
    "$INPUT" >> "$WRAPPED"

# Compile to SPIR-V
SPV="$TEMP_DIR/shader.spv"
if ! glslangValidator -V -S frag "$WRAPPED" -o "$SPV" 2>"$TEMP_DIR/glslang.log"; then
    echo "GLSL compilation failed for $INPUT:"
    cat "$TEMP_DIR/glslang.log"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Convert SPIR-V to Metal with unique function name
FUNC_NAME="fragment_${BASENAME}"
# Sanitize function name (replace non-alphanumeric with underscore)
FUNC_NAME=$(echo "$FUNC_NAME" | sed 's/[^a-zA-Z0-9_]/_/g')

if ! spirv-cross --msl "$SPV" --rename-entry-point main "$FUNC_NAME" frag --output "$OUTPUT" 2>"$TEMP_DIR/spirv.log"; then
    echo "SPIR-V to Metal conversion failed for $INPUT:"
    cat "$TEMP_DIR/spirv.log"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo "Converted: $BASENAME"
