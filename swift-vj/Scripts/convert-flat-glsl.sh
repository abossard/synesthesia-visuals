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
} _uniforms_;

layout(binding = 1) uniform sampler2D backbuffer;

layout(location = 0) out vec4 fragColor;

// Y-flip for Metal coordinate system compatibility
// Metal has Y=0 at top, OpenGL/Shadertoy has Y=0 at bottom
// MUST be defined BEFORE the macros to avoid _uniforms_.resolution expansion
vec4 _flipped_FragCoord() {
    return vec4(gl_FragCoord.x, _uniforms_.resolution.y - gl_FragCoord.y, gl_FragCoord.zw);
}

// GLSL compatibility - remap old uniforms to block members
#define time _uniforms_.time
#define resolution _uniforms_.resolution
#define mouse _uniforms_.mouse

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
    -e 's/float time([[:space:]]*=[[:space:]])/float _time\1/g' \
    -e 's/float round\(/float _round(/g' \
    -e 's/float sinh\(/float _sinh(/g' \
    -e 's/float cosh\(/float _cosh(/g' \
    -e 's/([^_a-zA-Z0-9])round\(/\1_round(/g' \
    -e 's/([^_a-zA-Z0-9])sinh\(/\1_sinh(/g' \
    -e 's/([^_a-zA-Z0-9])cosh\(/\1_cosh(/g' \
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
