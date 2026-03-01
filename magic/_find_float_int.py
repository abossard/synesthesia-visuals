#!/usr/bin/env python3
"""Find ALL patterns that could cause 'Incompatible types (float and int) in assignment'"""
import re

fname = 'ISF-bareimage/Release.5/IM-EmoCube-Complex+.fs'
with open(fname) as f:
    lines = f.readlines()

for i in range(142, len(lines)):
    line = lines[i].rstrip()
    
    # Pattern 1: float var assigned bare int: var=N; or var=N,
    for m in re.finditer(r'(\w+)\s*=\s*(-?\d+)\s*([;,\)])', line):
        varname = m.group(1)
        val = m.group(2)
        # Skip int declarations
        before = line[:m.start()]
        if re.search(r'\bint\s+$', before) or re.search(r'\bint\s+\w+\s*$', before):
            continue
        # Skip array indices
        if '[' in before[-3:]:
            continue
        # Skip if val already has a dot after it
        full = m.group(0)
        if '.' in val:
            continue
        # Check if it's a float context (heuristic)
        print(f"  L{i+1}: {varname}={val}{m.group(3)}  ctx: ...{line[max(0,m.start()-30):m.end()+10].strip()}")

    # Pattern 2: vec constructor with bare ints (already handled but check)
    for m in re.finditer(r'vec[234]\([^)]*\b(\d+)\b[^.)][^)]*\)', line):
        # Only if bare int without a dot
        inner = m.group(0)
        # Find ints in the inner
        for n in re.finditer(r'(?<![.0-9a-zA-Z_])(\d+)(?![.0-9])', inner):
            print(f"  L{i+1}: vec with bare int: {inner[:60]}")
            break
