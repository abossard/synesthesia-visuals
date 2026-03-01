#!/usr/bin/env python3
"""Fix the over-aggressive bare int conversion: restore ints in int contexts."""
import re

for fname in ['ISF-bareimage/Release.5/IM-EmoCube-Complex+.fs',
              'ISF-bareimage/Release.5/IM-EmoCube-Complex.fs']:
    with open(fname) as f:
        content = f.read()
    
    # Fix for(int X=N.0 -> for(int X=N  (int init must use int literal)
    content = re.sub(r'for\(int (\w+)=(-?\d+)\.0', r'for(int \1=\2', content)
    
    # Fix for(int X=N.0; -> same
    content = re.sub(r'for\(int (\w+)\s*=\s*(-?\d+)\.0\s*;', r'for(int \1=\2;', content)
    
    # Fix p_int==N.0 -> p_int==N  (int comparison)
    content = re.sub(r'p_int==(\d+)\.0', r'p_int==\1', content)
    
    # Fix int i=N.0;i<M -> int i=N;i<M
    content = re.sub(r'(int \w+=)(-?\d+)\.0(;)', r'\1\2\3', content)
    
    # Fix i<64.0 in int for-loop -> i<64
    # Actually for int loop: for(int i=0;i<64;  the 64 should stay int
    # The regex already caught i=0.0 above, but i<64 wasn't broken (it was already int+int)
    
    # Fix vec2(i,j) where i,j are int loop vars - these should stay int
    # Actually vec2(int,int) is fine in GLSL, it auto-converts
    
    with open(fname, 'w') as f:
        f.write(content)
    print(f'{fname}: int contexts restored')
