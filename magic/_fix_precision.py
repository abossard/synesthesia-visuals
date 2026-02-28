#!/usr/bin/env python3
"""Fix precision qualifiers and tanh() calls in Magic ISF shaders.
Run from the magic/ directory. Idempotent — safe to re-run."""
import re, os, subprocess

os.chdir(os.path.dirname(os.path.abspath(__file__)))

# --- Polyfill snippets ---
POLYFILL_FLOAT = """// _tanh polyfill for GLSL 1.20 (no built-in tanh)
float _tanh(float x) {
    float e2x = exp(2.0 * clamp(x, -20.0, 20.0));
    return (e2x - 1.0) / (e2x + 1.0);
}"""

POLYFILL_VEC3 = """vec3 _tanh(vec3 v) {
    return vec3(_tanh(v.x), _tanh(v.y), _tanh(v.z));
}"""

POLYFILL_VEC4 = """vec4 _tanh(vec4 v) {
    return vec4(_tanh(v.x), _tanh(v.y), _tanh(v.z), _tanh(v.w));
}"""


def find_json_end(lines):
    """Find the line index where the ISF JSON block ends (the line containing */)."""
    for i, l in enumerate(lines):
        if '*/' in l:
            return i
    return -1


def find_first_code_line(lines, after_idx):
    """Find first non-empty, non-comment line after a given index."""
    for i in range(after_idx + 1, len(lines)):
        stripped = lines[i].strip()
        if stripped and not stripped.startswith('//'):
            return i
    return after_idx + 1


def strip_existing_polyfill(content):
    """Remove previously injected _tanh polyfill blocks (including misplaced ones)."""
    # Remove full polyfill block (comment + float + optional vec3/vec4 overloads)
    content = re.sub(
        r'\n?// _tanh polyfill for GLSL 1\.20[^\n]*\n'
        r'float _tanh\(float x\) \{[^}]+\}\n'
        r'(?:vec[34] _tanh\(vec[34] v\) \{[^}]+\}\n)*',
        '\n', content
    )
    # Remove standalone vec overloads that might be separated
    content = re.sub(r'vec[34] _tanh\(vec[34] v\) \{[^}]+\}\n?', '', content)
    # Clean up multiple blank lines left behind
    content = re.sub(r'\n{3,}', '\n\n', content)
    return content


def fix_file(fpath, types_needed):
    """Fix tanh() calls in a single file. Returns True if modified."""
    with open(fpath, 'r') as f:
        content = f.read()

    # Step 1: Strip any existing (possibly misplaced) polyfill
    content = strip_existing_polyfill(content)

    # Step 2: Revert _tanh back to tanh so we can do a clean pass
    content = content.replace('_tanh(', 'tanh(')

    # Step 3: Check if there are actual tanh() calls needing fix
    if not re.search(r'\btanh\(', content):
        with open(fpath, 'w') as f:
            f.write(content)
        return False

    lines = content.split('\n')

    # Step 4: Find insertion point — after JSON close (*/)
    json_end = find_json_end(lines)
    if json_end < 0:
        print(f"  ERROR: No JSON block end found in {fpath}")
        return False

    first_code = find_first_code_line(lines, json_end)

    # Step 5: Build polyfill block
    polyfill_parts = [POLYFILL_FLOAT]
    if "vec3" in types_needed:
        polyfill_parts.append(POLYFILL_VEC3)
    if "vec4" in types_needed:
        polyfill_parts.append(POLYFILL_VEC4)
    polyfill_block = '\n'.join(polyfill_parts)

    # Step 6: Insert polyfill before first code line (after JSON + comments)
    lines.insert(first_code, polyfill_block + '\n')

    # Step 7: Rejoin and replace tanh( -> _tanh(
    new_content = '\n'.join(lines)
    new_content = re.sub(r'(?<!_)\btanh\(', '_tanh(', new_content)

    with open(fpath, 'w') as f:
        f.write(new_content)
    return True


# ============================================================
# PART 1: Fix precision qualifiers (scan all .fs files)
# ============================================================
print("=== PART 1: Fixing precision qualifiers ===")
p_fixed = 0
result = subprocess.run(
    ['grep', '-rl', '--include=*.fs', 'precision'],
    capture_output=True, text=True, cwd='.'
)
for fpath in result.stdout.strip().split('\n'):
    if not fpath:
        continue
    with open(fpath, 'r') as f:
        lines = f.readlines()
    modified = False
    for idx, line in enumerate(lines):
        if re.match(r'\s*precision\s+(highp|mediump|lowp)\s+float\s*;', line):
            lines[idx] = "// REMOVED for GLSL 1.20 (Magic): " + line.strip() + "\n"
            modified = True
            print(f"  FIXED: {fpath}:{idx+1}")
    if modified:
        with open(fpath, 'w') as f:
            f.writelines(lines)
        p_fixed += 1

print(f"  Files with precision fixes: {p_fixed}")

# ============================================================
# PART 2: Fix tanh() calls
# ============================================================
tanh_files = [
    ("ISF-bareimage/Release.2/IM-GlassFractalFlightTwist.fs", ["float", "vec4"]),
    ("ISF-bareimage/Release.2/IM_XORCORIDOR337.fs", ["float", "vec4"]),
    ("ISF-bareimage/Release.4/IM-MrBlob.fs", ["float", "vec4"]),
    ("ISF-bareimage/Release.4/IM-LOPYFrac3D-OrthoFractal-Evolution.fs", ["float", "vec3"]),
    ("ISF-bareimage/Release.4/IM-YONIM-TunnelFix-multipath-audioreactive-FINAL.fs", ["float", "vec4"]),
    ("ISF-bareimage/Release.3/IM-ROOT-COLOR-FINAL.fs", ["float"]),
    ("ISF-bareimage/Release.3/IM-Ascend.fs", ["float", "vec3"]),
    ("ISF-bareimage/Release.3/IM-ELCOSMO-FINAL.fs", ["float"]),
    ("ISF-bareimage/Release.3/IM-ELCOSMO-FINAL-OPT.fs", ["float"]),
    ("ISF-bareimage/Release.3/IM-Volt.fs", ["float", "vec4"]),
]

print("\n=== PART 2: Fixing tanh() calls ===")
t_fixed = 0
for fpath, types_needed in tanh_files:
    if fix_file(fpath, types_needed):
        t_fixed += 1
        print(f"  FIXED: {fpath} (overloads: {', '.join(types_needed)})")
    else:
        print(f"  SKIP (no tanh calls): {fpath}")

print(f"  Total tanh fixes: {t_fixed}")

# ============================================================
# PART 3: Verify
# ============================================================
print("\n=== VERIFICATION ===")
result = subprocess.run(
    ['grep', '-rn', '--include=*.fs', r'precision\s\+\(highp\|mediump\|lowp\)', '.'],
    capture_output=True, text=True
)
remaining = [l for l in result.stdout.strip().split('\n') if l and 'REMOVED' not in l]
print(f"  Precision: {'WARNING: ' + str(len(remaining)) + ' remaining' if remaining else 'OK'}")
for l in remaining:
    print(f"    {l}")

result2 = subprocess.run(
    ['grep', '-rn', '--include=*.fs', r'[^_]tanh(', '.'],
    capture_output=True, text=True
)
remaining2 = [l for l in result2.stdout.strip().split('\n')
              if l and '_tanh' not in l and 'tanh_safe' not in l and 'polyfill' not in l.lower() and l.strip()]
print(f"  tanh(): {'WARNING: ' + str(len(remaining2)) + ' remaining' if remaining2 else 'OK'}")
for l in remaining2:
    print(f"    {l}")

print("\nDone!")
