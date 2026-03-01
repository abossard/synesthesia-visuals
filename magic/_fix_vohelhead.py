#!/usr/bin/env python3
"""Fix GLSL 1.20 issues in Im-VohelHead-Icosahedron.fs:
1. Convert float[169](...) array constructors to init function
2. Replace transpose() with _transpose() polyfill
3. Fix const float phi = (1.0+sqrt(5.0))*0.5 to precomputed value
"""
import re

path = "ISF-bareimage/Release.5/Im-VohelHead-Icosahedron.fs"

with open(path, "r") as f:
    content = f.read()

# --- 1. Convert array constructors to init function ---
# Extract array data from each const float faceXxx[169] = float[169](...);
face_names = ["faceFront", "faceBack", "faceTop", "faceBottom", "faceLeft", "faceRight"]
face_data = {}

for name in face_names:
    pattern = rf'const float {name}\[169\] = float\[169\]\(([\s\S]*?)\);'
    m = re.search(pattern, content)
    if m:
        # Parse the values
        raw = m.group(1).strip()
        values = [v.strip() for v in raw.split(',') if v.strip()]
        face_data[name] = values
        print(f"  Found {name}: {len(values)} values")
    else:
        print(f"  WARNING: Could not find {name}")

# Remove the old const array declarations
for name in face_names:
    pattern = rf'const float {name}\[169\] = float\[169\]\([\s\S]*?\);\n'
    content = re.sub(pattern, '', content)

# Build the replacement: global arrays + init function
array_decls = "\n".join(f"float {name}[169];" for name in face_names)

init_lines = ["void initFaceData() {"]
for name in face_names:
    if name in face_data:
        for i, val in enumerate(face_data[name]):
            init_lines.append(f"    {name}[{i}]={val};")
init_lines.append("}")

init_function = "\n".join(init_lines)

# Insert after the comment "// --- Voxel Cube Data (13x13 Faces) ---"
old_comment = "// --- Voxel Cube Data (13x13 Faces) ---\n// Corrected arrays with proper size and GLSL syntax\n"
new_block = f"// --- Voxel Cube Data (13x13 Faces) ---\n{array_decls}\n{init_function}\n"
content = content.replace(old_comment, new_block)

# --- 2. Add initFaceData() call at start of main ---
# Find main() function and add call
content = content.replace(
    "void main() {",
    "void main() {\n    initFaceData();",
    1  # only first occurrence
)

# --- 3. Replace transpose() with _transpose() polyfill ---
# Add polyfill before the first function that uses it
polyfill = """mat3 _transpose(mat3 m) {
    return mat3(
        m[0][0], m[1][0], m[2][0],
        m[0][1], m[1][1], m[2][1],
        m[0][2], m[1][2], m[2][2]
    );
}
"""

# Insert before "// --- Shared Globals"
content = content.replace(
    "// --- Shared Globals (for passing data between functions) ---",
    polyfill + "// --- Shared Globals (for passing data between functions) ---"
)

# Replace transpose() calls
content = content.replace("transpose(g_rot)", "_transpose(g_rot)")
content = content.replace("transpose(g_icosahedronRot)", "_transpose(g_icosahedronRot)")

# --- 4. Fix const float phi = (1.0+sqrt(5.0))*0.5 ---
content = content.replace(
    "const float phi = (1.0+sqrt(5.0))*0.5; const float invphi = 1.0/phi;",
    "const float phi = 1.6180339887; const float invphi = 0.6180339887;"
)

with open(path, "w") as f:
    f.write(content)

print(f"\nFixed {path}")
print("  - Array constructors → init function")
print("  - transpose() → _transpose() polyfill")
print("  - const phi with sqrt → precomputed value")
