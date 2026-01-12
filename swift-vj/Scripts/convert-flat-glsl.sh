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
    float bin0;
    float bin1;
    float bin2;
    float zoom;
} _uniforms_;

layout(binding = 1) uniform sampler2D backbuffer;

layout(location = 0) out vec4 fragColor;

// Y-flip for Metal coordinate system compatibility
vec4 _flipped_FragCoord() {
    return vec4(gl_FragCoord.x, _uniforms_.resolution.y - gl_FragCoord.y, gl_FragCoord.zw);
}

// GLSL compatibility - remap uniforms to block members
#define time _uniforms_.time
#define resolution _uniforms_.resolution
#define mouse _uniforms_.mouse
#define speed _uniforms_.speed
#define bass _uniforms_.bass
#define lowMid _uniforms_.lowMid
#define mid _uniforms_.mid
#define highs _uniforms_.highs
#define level _uniforms_.level
#define kickEnv _uniforms_.kickEnv
#define kickPulse _uniforms_.kickPulse
#define beat _uniforms_.beat
#define energyFast _uniforms_.energyFast
#define energySlow _uniforms_.energySlow
#define bin0 _uniforms_.bin0
#define bin1 _uniforms_.bin1
#define bin2 _uniforms_.bin2
#define zoom _uniforms_.zoom

// texture2D -> texture for GLSL 4.5
#define texture2D texture

// Remove precision qualifiers (not needed in GLSL 450)
#define lowp
#define mediump  
#define highp

EOF

# Extract the main function body from the original shader
# Strip the uniform declarations, GL_ES blocks, precision stuff, varying
# Handle both leading whitespace and no whitespace variations
# Also rename local variables that shadow uniforms, and rename conflicting functions
# Replace gl_FragCoord with Y-flipped version for Metal compatibility
sed -E \
    -e '/^[[:space:]]*#ifdef GL_ES/,/^[[:space:]]*#endif/d' \
    -e '/^[[:space:]]*uniform /d' \
    -e '/^[[:space:]]*precision /d' \
    -e '/^[[:space:]]*varying /d' \
    -e '/^[[:space:]]*attribute /d' \
    -e 's/gl_FragColor/fragColor/g' \
    -e 's/gl_FragCoord/_flipped_FragCoord()/g' \
    -e 's/vec2 mouse([[:space:]]*=[[:space:]])/vec2 _mouse\1/g' \
    -e 's/float time([[:space:]]*=)/float _localTime\1/g' \
    -e 's/float time([[:space:]]*,)/float _t\1/g' \
    -e 's/float time([[:space:]]*\))/float _t\1/g' \
    -e 's/float round\(/float _round(/g' \
    -e 's/float sinh\(/float _sinh(/g' \
    -e 's/float cosh\(/float _cosh(/g' \
    -e 's/([^_a-zA-Z0-9])round\(/\1_round(/g' \
    -e 's/([^_a-zA-Z0-9])sinh\(/\1_sinh(/g' \
    -e 's/([^_a-zA-Z0-9])cosh\(/\1_cosh(/g' \
    -e 's/sampler2D bb/sampler2D backbuffer/g' \
    -e 's/texture2D\(bb,/texture(backbuffer,/g' \
    -e 's/texture\(bb,/texture(backbuffer,/g' \
    -e 's/([^_a-zA-Z0-9])bb([^_a-zA-Z0-9])/\1backbuffer\2/g' \
    -e 's/float filter([[:space:]]*=)/float _filter\1/g' \
    -e 's/([^_a-zA-Z0-9])filter([[:space:]]*[=\),;+*/-])/\1_filter\2/g' \
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
