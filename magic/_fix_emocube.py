#!/usr/bin/env python3
"""Fix remaining GLSL 1.20 issues in EmoCube-Complex files:
1. texture() -> texture2D()
2. int literals in vec constructors -> float literals
3. transpose() -> _transpose() polyfill (Complex+ only)
"""
import re

for fname in ['ISF-bareimage/Release.5/IM-EmoCube-Complex+.fs',
              'ISF-bareimage/Release.5/IM-EmoCube-Complex.fs']:
    with open(fname) as f:
        content = f.read()

    # 1) texture( -> texture2D( (skip already-converted texture2D)
    content = re.sub(r'(?<![2D])(?<!\w)texture\(', 'texture2D(', content)

    # 2) Fix int literals in vec/gl_FragColor constructors
    content = content.replace('vec4(float(colorPalette), 0, 0, 1)',
                              'vec4(float(colorPalette), 0.0, 0.0, 1.0)')
    content = content.replace('vec3(0, 0, -20)', 'vec3(0.0, 0.0, -20.0)')
    # Also fix vec3(sign(d.x),0,0) patterns etc
    content = re.sub(r'vec3\(sign\(d\.x\),\s*0,\s*0\)', 'vec3(sign(d.x),0.0,0.0)', content)
    content = re.sub(r'vec3\(0,\s*sign\(d\.y\),\s*0\)', 'vec3(0.0,sign(d.y),0.0)', content)
    content = re.sub(r'vec3\(0,\s*0,\s*sign\(d\.z\)\)', 'vec3(0.0,0.0,sign(d.z))', content)
    content = re.sub(r'vec3\(0,\s*sin\(', 'vec3(0.0,sin(', content)
    content = re.sub(r'vec3\(i\*0\.5,\s*0,\s*0\)', 'vec3(i*0.5,0.0,0.0)', content)
    content = re.sub(r'vec3\(0,\s*i\*0\.5,\s*0\)', 'vec3(0.0,i*0.5,0.0)', content)
    content = re.sub(r'vec3\(0,\s*0,\s*i\*0\.5\)', 'vec3(0.0,0.0,i*0.5)', content)
    # vec3(0,0,-20) variant without spaces
    content = content.replace('vec3(0,0,-20)', 'vec3(0.0,0.0,-20.0)')

    with open(fname, 'w') as f:
        f.write(content)
    print(f'{fname}: texture->texture2D + int literals fixed')

# 3) transpose() polyfill - only in Complex+
fname = 'ISF-bareimage/Release.5/IM-EmoCube-Complex+.fs'
with open(fname) as f:
    content = f.read()

transpose_polyfill = """// GLSL 1.20 polyfill: transpose not available
mat3 _transpose(mat3 m) {
    return mat3(
        m[0][0], m[1][0], m[2][0],
        m[0][1], m[1][1], m[2][1],
        m[0][2], m[1][2], m[2][2]
    );
}

"""
content = content.replace('// --- FXAA Implementation',
                          transpose_polyfill + '// --- FXAA Implementation')
content = content.replace('transpose(rotM)', '_transpose(rotM)')

with open(fname, 'w') as f:
    f.write(content)
print(f'{fname}: transpose polyfill added')
