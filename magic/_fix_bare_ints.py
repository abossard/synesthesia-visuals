#!/usr/bin/env python3
"""Fix all bare integer literals in vec/mat constructors and float assignments
in both EmoCube-Complex files."""
import re

for fname in ['ISF-bareimage/Release.5/IM-EmoCube-Complex+.fs',
              'ISF-bareimage/Release.5/IM-EmoCube-Complex.fs']:
    with open(fname) as f:
        content = f.read()

    # Find end of JSON header
    json_end = content.index('}*/')
    glsl = content[json_end+3:]  # everything after }*/

    # Fix vec2(0) -> vec2(0.0), vec3(0) -> vec3(0.0), vec4(0) -> vec4(0.0)
    glsl = re.sub(r'(vec[234])\((\d+)\)', lambda m: f'{m.group(1)}({m.group(2)}.0)', glsl)

    # Fix bare ints in vec4(6,1,2,0) patterns -> vec4(6.0,1.0,2.0,0.0)
    # Match vec4(int,int,int,int) with possible negatives and mixed float/int
    def fix_vec_args(m):
        prefix = m.group(1)  # vec2/vec3/vec4(
        args = m.group(2)
        # Split by comma, fix each arg
        parts = args.split(',')
        fixed = []
        for p in parts:
            p = p.strip()
            # If it's a bare integer (no dot, no variable chars beyond digits and minus)
            if re.match(r'^-?\d+$', p):
                fixed.append(p + '.0')
            else:
                fixed.append(p)
        return prefix + ','.join(fixed) + ')'

    glsl = re.sub(r'(vec[234]\()([^)]+)\)', fix_vec_args, glsl)

    # Fix mat2(cos(...+vec4(...))) - the vec4 args inside are already handled above
    # Fix bare int in mat3 constructors (already done for rotationX/Y/Z but check others)

    # Fix float assignment: v=0; -> v=0.0;
    glsl = re.sub(r'(?<=[=,])0(?=[;,\)])', '0.0', glsl)
    # But be careful not to double-fix: 0.0.0 
    glsl = glsl.replace('0.0.0', '0.0')

    # Fix standalone 1 in float context: return to be safe, skip
    # Fix +1.) patterns - these are fine (1. is float)
    
    content = content[:json_end+3] + glsl

    with open(fname, 'w') as f:
        f.write(content)
    print(f'{fname}: bare int literals fixed')
