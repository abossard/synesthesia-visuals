#!/usr/bin/env python3
"""
Analyze ISF shader files and match uniforms against audio binding patterns.
"""

import os
import json
import re
from pathlib import Path

# Audio binding patterns from the request
AUDIO_PATTERNS = {
    'energyFast': ['speed', 'rate', 'velocity'],
    'bass': ['scale', 'zoom', 'size', 'freq', 'wave', 'radius', 'width', 'thick', 'stroke', 'line'],
    'level': ['intensity', 'brightness', 'amount', 'strength', 'power', 'iter', 'step', 'detail', 'octave', 'glow', 'bloom', 'bright', 'lumi', 'emit', 'contrast', 'gamma', 'curve'],
    'kickEnv': ['distort', 'warp', 'noise', 'glitch', 'chaos', 'pulse', 'beat', 'kick', 'hit', 'impact'],
    'mid': ['rotat', 'angle', 'spin', 'turb', 'complex', 'density', 'rough'],
    'highs': ['offset', 'shift', 'displace', 'seed', 'rnd', 'random', 'jitter'],
    'energySlow': ['blend', 'mix', 'fade', 'alpha', 'opacity', 'morph', 'transform', 'evolve', 'mutate'],
}

def extract_isf_json(shader_content):
    """Extract the JSON header from ISF shader content."""
    # ISF format: JSON block between /* and */
    match = re.search(r'/\*\s*(\{.*?\})\s*\*/', shader_content, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            return None
    return None

def get_uniform_names(isf_json):
    """Extract uniform names from INPUTS array."""
    if not isf_json or 'INPUTS' not in isf_json:
        return []
    
    uniforms = []
    for inp in isf_json.get('INPUTS', []):
        if 'NAME' in inp:
            uniforms.append({
                'name': inp['NAME'],
                'type': inp.get('TYPE', 'unknown'),
                'min': inp.get('MIN'),
                'max': inp.get('MAX'),
                'default': inp.get('DEFAULT')
            })
    return uniforms

def match_uniform_to_audio(uniform_name):
    """Check if a uniform name matches any audio binding pattern."""
    name_lower = uniform_name.lower()
    
    for audio_source, patterns in AUDIO_PATTERNS.items():
        for pattern in patterns:
            if pattern in name_lower:
                return audio_source, pattern
    
    return None, None

def analyze_shader_file(filepath):
    """Analyze a single shader file."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {'error': str(e)}
    
    isf_json = extract_isf_json(content)
    if not isf_json:
        return {'error': 'No valid ISF JSON header found'}
    
    uniforms = get_uniform_names(isf_json)
    
    matched = []
    unmatched = []
    
    for uniform in uniforms:
        audio_source, pattern = match_uniform_to_audio(uniform['name'])
        if audio_source:
            matched.append({
                'name': uniform['name'],
                'type': uniform['type'],
                'audio_source': audio_source,
                'matched_pattern': pattern
            })
        else:
            unmatched.append({
                'name': uniform['name'],
                'type': uniform['type']
            })
    
    return {
        'shader_name': isf_json.get('DESCRIPTION', os.path.basename(filepath)),
        'uniforms_total': len(uniforms),
        'matched': matched,
        'unmatched': unmatched,
        'match_ratio': len(matched) / len(uniforms) if uniforms else 0
    }

def main():
    base_path = Path('/Users/abossard/Desktop/projects/synesthesia-visuals/processing-vj/src/VJUniverse/data/shaders/isf')
    
    # Find all .fs files
    shader_files = list(base_path.rglob('*.fs'))
    
    results = []
    
    for shader_file in sorted(shader_files):
        result = analyze_shader_file(shader_file)
        result['filepath'] = str(shader_file.relative_to(base_path))
        results.append(result)
    
    # Print summary table
    print("\n" + "="*120)
    print("ISF SHADER AUDIO BINDING ANALYSIS")
    print("="*120)
    
    # Sort by match ratio (most matches first)
    results.sort(key=lambda x: (x.get('match_ratio', 0), len(x.get('matched', []))), reverse=True)
    
    print(f"\n{'Shader File':<50} {'Total':<6} {'Bound':<6} {'Unbound':<6} {'Ratio':<8}")
    print("-"*120)
    
    for r in results:
        if 'error' in r:
            print(f"{r['filepath']:<50} ERROR: {r['error']}")
            continue
            
        filepath = r['filepath'][:48] if len(r['filepath']) > 48 else r['filepath']
        print(f"{filepath:<50} {r['uniforms_total']:<6} {len(r['matched']):<6} {len(r['unmatched']):<6} {r['match_ratio']:.1%}")
    
    # Detailed breakdown for shaders with matches
    print("\n" + "="*120)
    print("DETAILED BINDINGS (Shaders with audio-reactive uniforms)")
    print("="*120)
    
    for r in results:
        if 'error' in r or not r.get('matched'):
            continue
        
        print(f"\n📁 {r['filepath']}")
        print(f"   Shader: {r.get('shader_name', 'N/A')}")
        
        if r['matched']:
            print("   ✅ WILL BE BOUND:")
            for m in r['matched']:
                print(f"      • {m['name']} ({m['type']}) → {m['audio_source']} (pattern: '{m['matched_pattern']}')")
        
        if r['unmatched']:
            print("   ❌ WON'T BE BOUND:")
            for u in r['unmatched']:
                print(f"      • {u['name']} ({u['type']})")
    
    # Summary statistics
    print("\n" + "="*120)
    print("SUMMARY STATISTICS")
    print("="*120)
    
    total_shaders = len([r for r in results if 'error' not in r])
    shaders_with_matches = len([r for r in results if r.get('matched')])
    total_uniforms = sum(r.get('uniforms_total', 0) for r in results if 'error' not in r)
    total_matched = sum(len(r.get('matched', [])) for r in results)
    total_unmatched = sum(len(r.get('unmatched', [])) for r in results)
    
    print(f"\nTotal shaders analyzed: {total_shaders}")
    print(f"Shaders with audio bindings: {shaders_with_matches} ({shaders_with_matches/total_shaders*100:.0f}%)")
    print(f"Total uniforms found: {total_uniforms}")
    print(f"Uniforms that WILL be bound: {total_matched} ({total_matched/total_uniforms*100:.0f}%)")
    print(f"Uniforms that WON'T be bound: {total_unmatched} ({total_unmatched/total_uniforms*100:.0f}%)")
    
    # Audio source usage breakdown
    print("\n📊 Audio Source Usage:")
    source_counts = {}
    for r in results:
        for m in r.get('matched', []):
            src = m['audio_source']
            source_counts[src] = source_counts.get(src, 0) + 1
    
    for src, count in sorted(source_counts.items(), key=lambda x: -x[1]):
        print(f"   {src}: {count} bindings")
    
    # Top recommendations
    print("\n🎯 TOP SHADERS FOR AUDIO REACTIVITY (by bound uniforms):")
    top_shaders = [r for r in results if r.get('matched')][:10]
    for i, r in enumerate(top_shaders, 1):
        print(f"   {i}. {r['filepath']} ({len(r['matched'])} bindings)")

if __name__ == '__main__':
    main()
