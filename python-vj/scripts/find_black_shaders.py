#!/usr/bin/env python3
"""
Find black/broken shaders by analyzing screenshots.

Uses ImageMagick to calculate mean brightness of each screenshot.
Shaders with very dark screenshots (mean < threshold) are likely broken.
"""

import subprocess
import sys
from pathlib import Path
from typing import List, Tuple

# Default paths relative to project root
DEFAULT_SCREENSHOTS_DIR = Path(__file__).parent.parent.parent / "processing-vj/src/VJUniverse/data/screenshots"
DEFAULT_SHADERS_ISF = Path(__file__).parent.parent.parent / "processing-vj/src/VJUniverse/data/shaders/isf"
DEFAULT_SHADERS_GLSL = Path(__file__).parent.parent.parent / "processing-vj/src/VJUniverse/data/shaders/glsl"

# Brightness threshold (0-255) - below this is considered "black"
BLACK_THRESHOLD = 5.0


def get_image_brightness(image_path: Path) -> float:
    """Get mean brightness of an image using ImageMagick."""
    try:
        result = subprocess.run(
            ["identify", "-format", "%[fx:mean*255]", str(image_path)],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return float(result.stdout.strip())
    except (subprocess.TimeoutExpired, ValueError, subprocess.SubprocessError) as e:
        print(f"  Warning: Could not analyze {image_path.name}: {e}", file=sys.stderr)
    return -1.0


def find_shader_path(shader_name: str, isf_dir: Path, glsl_dir: Path) -> str:
    """Find the shader file path given a screenshot name."""
    # Remove .png extension and common suffixes
    base_name = shader_name.replace(".png", "")
    
    # Handle names like "ShaderName_ShaderName" -> "ShaderName"
    if "_" in base_name:
        parts = base_name.split("_")
        if len(parts) == 2 and parts[0] == parts[1]:
            base_name = parts[0]
    
    # Check ISF directory
    isf_path = isf_dir / f"{base_name}.fs"
    if isf_path.exists():
        return f"isf/{base_name}.fs"
    
    # Check GLSL directory
    glsl_path = glsl_dir / f"{base_name}.txt"
    if glsl_path.exists():
        return f"glsl/{base_name}.txt"
    
    # Try without spaces
    base_no_spaces = base_name.replace(" ", "")
    isf_path = isf_dir / f"{base_no_spaces}.fs"
    if isf_path.exists():
        return f"isf/{base_no_spaces}.fs"
    
    glsl_path = glsl_dir / f"{base_no_spaces}.txt"
    if glsl_path.exists():
        return f"glsl/{base_no_spaces}.txt"
    
    return f"?/{base_name} (not found)"


def analyze_screenshots(
    screenshots_dir: Path,
    isf_dir: Path,
    glsl_dir: Path,
    threshold: float = BLACK_THRESHOLD,
    verbose: bool = False
) -> List[Tuple[str, str, float]]:
    """
    Analyze all screenshots and return list of black/broken ones.
    
    Returns: List of (screenshot_name, shader_path, brightness)
    """
    black_shaders = []
    all_results = []
    
    png_files = sorted(screenshots_dir.glob("*.png"))
    total = len(png_files)
    
    print(f"Analyzing {total} screenshots...", file=sys.stderr)
    
    for i, png_path in enumerate(png_files, 1):
        if verbose:
            print(f"  [{i}/{total}] {png_path.name}", file=sys.stderr)
        
        brightness = get_image_brightness(png_path)
        shader_path = find_shader_path(png_path.name, isf_dir, glsl_dir)
        
        all_results.append((png_path.name, shader_path, brightness))
        
        if 0 <= brightness < threshold:
            black_shaders.append((png_path.name, shader_path, brightness))
    
    return black_shaders, all_results


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Find black/broken shaders from screenshots")
    parser.add_argument("--screenshots", "-s", type=Path, default=DEFAULT_SCREENSHOTS_DIR,
                        help="Screenshots directory")
    parser.add_argument("--isf", type=Path, default=DEFAULT_SHADERS_ISF,
                        help="ISF shaders directory")
    parser.add_argument("--glsl", type=Path, default=DEFAULT_SHADERS_GLSL,
                        help="GLSL shaders directory")
    parser.add_argument("--threshold", "-t", type=float, default=BLACK_THRESHOLD,
                        help=f"Brightness threshold (0-255), default {BLACK_THRESHOLD}")
    parser.add_argument("--all", "-a", action="store_true",
                        help="Show all shaders with brightness values")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose output")
    parser.add_argument("--output", "-o", type=Path,
                        help="Output file (default: stdout)")
    
    args = parser.parse_args()
    
    if not args.screenshots.exists():
        print(f"Error: Screenshots directory not found: {args.screenshots}", file=sys.stderr)
        sys.exit(1)
    
    black_shaders, all_results = analyze_screenshots(
        args.screenshots,
        args.isf,
        args.glsl,
        args.threshold,
        args.verbose
    )
    
    # Build output
    lines = []
    
    if args.all:
        lines.append("# All Shaders by Brightness")
        lines.append(f"# Threshold: {args.threshold}")
        lines.append("")
        lines.append(f"{'Brightness':>10}  {'Status':<8}  {'Shader Path'}")
        lines.append("-" * 70)
        
        for name, path, brightness in sorted(all_results, key=lambda x: x[2]):
            status = "BLACK" if 0 <= brightness < args.threshold else "OK"
            lines.append(f"{brightness:>10.2f}  {status:<8}  {path}")
    else:
        lines.append(f"# Black/Broken Shaders (brightness < {args.threshold})")
        lines.append(f"# Found: {len(black_shaders)} black shaders")
        lines.append("")
        
        for name, path, brightness in sorted(black_shaders, key=lambda x: x[2]):
            lines.append(f"{path}  # brightness={brightness:.2f}")
    
    output = "\n".join(lines)
    
    if args.output:
        args.output.write_text(output)
        print(f"Written to {args.output}", file=sys.stderr)
    else:
        print(output)
    
    # Summary to stderr
    print(f"\nSummary: {len(black_shaders)} black shaders out of {len(all_results)} total", file=sys.stderr)


if __name__ == "__main__":
    main()
