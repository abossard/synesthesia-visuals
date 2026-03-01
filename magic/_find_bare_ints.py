#!/usr/bin/env python3
"""Find all bare integer literals in GLSL code of EmoCube-Complex+.fs"""
import re

fname = 'ISF-bareimage/Release.5/IM-EmoCube-Complex+.fs'
with open(fname) as f:
    lines = f.readlines()

for i in range(142, len(lines)):
    line = lines[i]
    if line.strip().startswith('//'):
        continue
    # Find bare int literals: digit(s) not preceded/followed by alphanumeric/dot
    for m in re.finditer(r'(?<![0-9a-zA-Z_.\[])(\d+)(?![0-9.xXa-fA-Fu\]])', line):
        val = m.group(1)
        ctx = line[max(0, m.start()-20):min(len(line), m.end()+20)]
        # Skip FRAMEINDEX/PASSINDEX comparisons, initFaceData calls, for-loop int indices
        skip_words = ['FRAMEINDEX', 'PASSINDEX', 'initFace', 'int(', 'p_int==']
        if any(w in ctx for w in skip_words):
            continue
        # Skip array indices like [0], [1], [2]
        if m.start() > 0 and line[m.start()-1] == '[':
            continue
        # Skip the initFaceData function body
        if 'face' in line[:30] and '=' in line[:50]:
            continue
        print(f'  line {i+1}: bare int "{val}" ... {ctx.strip()}')
