#!/usr/bin/env python3
"""
Processing Sketch Discovery Script

Automatically discovers Processing sketches in the repository and 
generates/updates the ci-test-config.json file.

Usage: python3 discover-sketches.py [--update]
"""

import os
import json
import re
import argparse
from pathlib import Path

def has_setup_and_draw(file_path):
    """Check if a .pde file has both setup() and draw() functions"""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            return 'void setup()' in content and 'void draw()' in content
    except:
        return False

def discover_sketches(base_dir):
    """
    Discover all Processing sketches in the given directory.
    
    A directory is considered a sketch if:
    1. It contains at least one .pde file with setup() and draw()
    2. The folder name matches at least one .pde file name, OR
    3. There is exactly one .pde with setup/draw and others are helpers
    """
    sketches = []
    base_path = Path(base_dir)
    
    # Find all directories containing .pde files
    for root, dirs, files in os.walk(base_path):
        # Skip hidden directories and 'lib' directory
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'lib']
        
        pde_files = [f for f in files if f.endswith('.pde')]
        if not pde_files:
            continue
        
        folder_name = os.path.basename(root)
        
        # Check if folder name matches a .pde file
        main_file = None
        if f"{folder_name}.pde" in pde_files:
            # Check if this file has setup/draw
            main_path = os.path.join(root, f"{folder_name}.pde")
            if has_setup_and_draw(main_path):
                main_file = f"{folder_name}.pde"
        
        # If no match, look for exactly one file with setup/draw
        if not main_file:
            setup_draw_files = [
                f for f in pde_files 
                if has_setup_and_draw(os.path.join(root, f))
            ]
            
            if len(setup_draw_files) == 1:
                main_file = setup_draw_files[0]
            elif len(setup_draw_files) > 1:
                print(f"⚠️  Warning: {root} has multiple files with setup/draw: {setup_draw_files}")
                continue
        
        if main_file:
            # Get relative path from base_dir
            rel_path = os.path.relpath(root, base_path.parent)
            
            sketch_info = {
                "name": folder_name,
                "path": rel_path,
                "mainFile": main_file,
                "testScenarios": [
                    {
                        "name": "initial-state",
                        "description": f"Capture initial state of {folder_name}",
                        "waitFrames": 60,
                        "keyInputs": [],
                        "screenshotName": f"{folder_name.lower()}-initial.png"
                    }
                ]
            }
            
            sketches.append(sketch_info)
    
    return sorted(sketches, key=lambda x: x['name'])

def main():
    parser = argparse.ArgumentParser(description='Discover Processing sketches')
    parser.add_argument('--update', action='store_true', 
                       help='Update existing config preserving test scenarios')
    parser.add_argument('--output', default='processing-vj/ci-test-config.json',
                       help='Output configuration file')
    args = parser.parse_args()
    
    # Discover sketches
    print("Discovering Processing sketches...")
    base_dir = 'processing-vj'
    
    if not os.path.exists(base_dir):
        print(f"Error: {base_dir} not found")
        return 1
    
    discovered = discover_sketches(base_dir)
    
    print(f"\nFound {len(discovered)} sketches:")
    for sketch in discovered:
        print(f"  • {sketch['name']} ({sketch['path']})")
    
    # Load existing config if updating
    existing_config = {}
    if args.update and os.path.exists(args.output):
        try:
            with open(args.output, 'r') as f:
                existing_data = json.load(f)
                # Create lookup by name
                for sketch in existing_data.get('sketches', []):
                    existing_config[sketch['name']] = sketch
        except Exception as e:
            print(f"Warning: Could not read existing config: {e}")
    
    # Merge with existing config if updating
    if args.update and existing_config:
        for sketch in discovered:
            if sketch['name'] in existing_config:
                # Preserve test scenarios from existing config
                sketch['testScenarios'] = existing_config[sketch['name']]['testScenarios']
                print(f"  ✓ Preserved test scenarios for {sketch['name']}")
    
    # Write config
    config = {
        "sketches": discovered
    }
    
    with open(args.output, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"\n✅ Configuration written to {args.output}")
    return 0

if __name__ == '__main__':
    exit(main())
