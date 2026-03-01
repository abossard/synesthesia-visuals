#!/usr/bin/env python3
"""Convert GLSL 1.30+ array constructors to GLSL 1.20 compatible init-in-function pattern."""
import re, sys

def fix_file(fpath):
    with open(fpath, 'r') as f:
        content = f.read()

    pattern = r'const float (\w+)\[169\] = float\[169\]\(\n((?:[\d\., \n]+\n?)+?)\);'
    matches = list(re.finditer(pattern, content))
    if not matches:
        print(f"No array constructors found in {fpath}")
        return

    print(f"Found {len(matches)} array declarations in {fpath}")

    init_lines = []
    decl_lines = []
    for m in matches:
        name = m.group(1)
        data_str = m.group(2)
        vals = [v.strip() for v in data_str.replace('\n', '').split(',') if v.strip()]
        print(f"  {name}: {len(vals)} values")
        decl_lines.append(f"float {name}[169];")
        for i, v in enumerate(vals):
            init_lines.append(f"{name}[{i}]={v};")

    # Build compact init function (6 assignments per line)
    init_func = "void initFaceData() {\n"
    for i in range(0, len(init_lines), 6):
        chunk = " ".join(init_lines[i:i+6])
        init_func += f"    {chunk}\n"
    init_func += "}\n"

    # Replace original array blocks
    first_start = content.rfind('\n', 0, matches[0].start()) + 1
    last_end = matches[-1].end()

    before = content[:first_start]
    after = content[last_end:]

    new_content = before
    new_content += "// --- Voxel Cube Data (GLSL 1.20 compatible) ---\n"
    new_content += "\n".join(decl_lines) + "\n\n"
    new_content += init_func
    new_content += after

    # Add initFaceData() call at start of main()
    new_content = new_content.replace(
        'void main() {\n    if (PASSINDEX == 0)',
        'void main() {\n    initFaceData();\n    if (PASSINDEX == 0)'
    )

    with open(fpath, 'w') as f:
        f.write(new_content)
    print(f"Done! {fpath} converted to GLSL 1.20 init-in-function pattern")

if __name__ == '__main__':
    for f in sys.argv[1:]:
        fix_file(f)
