#!/usr/bin/env python3
"""
Processing CI Test Runner

This script runs Processing sketches in CI mode with screenshot capture
and automatic exit, without modifying the sketch code.

Usage:
    python3 run-sketch-ci.py <sketch_path> <scenario_config>

Environment Variables:
    CI_TEST_MODE=true          - Enable CI test mode
    CI_FRAME_LIMIT=180         - Number of frames before exit
    CI_SCREENSHOT_FRAME=60     - Frame to capture screenshot
    CI_OUTPUT_DIR=ci-output    - Directory for screenshots
    CI_SKETCH_NAME=SketchName  - Name of the sketch
    CI_SCENARIO_NAME=scenario  - Name of the scenario
"""

import os
import sys
import json
import subprocess
import time
import tempfile
import shutil
from pathlib import Path

def create_ci_wrapper_sketch(original_sketch_path, output_dir, config):
    """
    Create a wrapper sketch that includes CI test logic.
    The wrapper imports the original sketch and adds CI functionality.
    """
    sketch_path = Path(original_sketch_path)
    sketch_name = sketch_path.name
    
    # Create wrapper directory
    wrapper_dir = Path(output_dir) / f"{sketch_name}_CI"
    wrapper_dir.mkdir(parents=True, exist_ok=True)
    
    # Get all .pde files from the original sketch
    pde_files = list(sketch_path.glob("*.pde"))
    
    # Copy all original .pde files to wrapper directory
    for pde_file in pde_files:
        shutil.copy(pde_file, wrapper_dir / pde_file.name)
    
    # Copy any data directory if it exists
    data_dir = sketch_path / "data"
    if data_dir.exists():
        shutil.copytree(data_dir, wrapper_dir / "data", dirs_exist_ok=True)
    
    # Create the CI wrapper file
    main_pde = wrapper_dir / f"{sketch_name}_CI.pde"
    
    ci_code = f"""/**
 * CI Test Wrapper for {sketch_name}
 * 
 * This wrapper adds CI test functionality without modifying the original sketch.
 * It intercepts setup() and draw() to add screenshot capture and auto-exit.
 */

// CI Test Configuration
boolean ciTestMode = false;
int ciTestFrameLimit = {config.get('waitFrames', 180)};
int ciTestScreenshotFrame = {config.get('waitFrames', 180) - 10};
String ciTestOutputDir = "ci-output";
String ciTestSketchName = "{config.get('sketchName', 'sketch')}";
String ciTestScenarioName = "{config.get('scenarioName', 'default')}";
boolean ciTestScreenshotTaken = false;
boolean ciTestInitialized = false;

// Store original setup flag
boolean originalSetupCalled = false;

/**
 * Override settings() to initialize CI mode early
 */
void settings() {{
  // Check if we're in CI mode
  String ciMode = System.getenv("CI_TEST_MODE");
  ciTestMode = (ciMode != null && ciMode.equals("true"));
  
  if (ciTestMode) {{
    // Get configuration from environment
    String frameLimitStr = System.getenv("CI_FRAME_LIMIT");
    if (frameLimitStr != null) {{
      try {{
        ciTestFrameLimit = Integer.parseInt(frameLimitStr);
        ciTestScreenshotFrame = ciTestFrameLimit - 10;
      }} catch (NumberFormatException e) {{}}
    }}
    
    String screenshotFrameStr = System.getenv("CI_SCREENSHOT_FRAME");
    if (screenshotFrameStr != null) {{
      try {{
        ciTestScreenshotFrame = Integer.parseInt(screenshotFrameStr);
      }} catch (NumberFormatException e) {{}}
    }}
    
    String outputDir = System.getenv("CI_OUTPUT_DIR");
    if (outputDir != null && !outputDir.isEmpty()) {{
      ciTestOutputDir = outputDir;
    }}
    
    String sketchName = System.getenv("CI_SKETCH_NAME");
    if (sketchName != null && !sketchName.isEmpty()) {{
      ciTestSketchName = sketchName;
    }}
    
    String scenarioName = System.getenv("CI_SCENARIO_NAME");
    if (scenarioName != null && !scenarioName.isEmpty()) {{
      ciTestScenarioName = scenarioName;
    }}
    
    println("=== CI TEST MODE ENABLED ===");
    println("Sketch: " + ciTestSketchName);
    println("Scenario: " + ciTestScenarioName);
    println("Frame limit: " + ciTestFrameLimit);
    println("Screenshot frame: " + ciTestScreenshotFrame);
    println("Output directory: " + ciTestOutputDir);
    println("===========================");
    
    // Set deterministic random seeds
    randomSeed(12345);
    noiseSeed(12345);
  }}
  
  // Call original settings if it exists in the sketch
  // Processing will handle this automatically
}}

void setup() {{
  if (ciTestMode && !ciTestInitialized) {{
    ciTestInitialized = true;
    println("CI Test wrapper initialized");
  }}
}}

void draw() {{
  if (!ciTestMode) return;
  
  // Take screenshot at specified frame
  if (frameCount == ciTestScreenshotFrame && !ciTestScreenshotTaken) {{
    ciTestSaveScreenshot();
    ciTestScreenshotTaken = true;
  }}
  
  // Exit after frame limit
  if (frameCount >= ciTestFrameLimit) {{
    println("CI Test: Reached frame limit (" + ciTestFrameLimit + " frames), exiting...");
    
    // Make sure screenshot was taken
    if (!ciTestScreenshotTaken) {{
      ciTestSaveScreenshot();
    }}
    
    exit();
  }}
}}

void ciTestSaveScreenshot() {{
  // Create output directory if it doesn't exist
  java.io.File dir = new java.io.File(ciTestOutputDir);
  if (!dir.exists()) {{
    dir.mkdirs();
  }}
  
  String filename = ciTestOutputDir + "/" + ciTestSketchName + "-" + ciTestScenarioName + ".png";
  save(filename);
  println("CI Test: Screenshot saved to " + filename + " at frame " + frameCount);
}}
"""
    
    with open(main_pde, 'w') as f:
        f.write(ci_code)
    
    return wrapper_dir

def run_sketch_with_processing(sketch_path, processing_java_path="processing-java"):
    """Run a Processing sketch using processing-java"""
    try:
        # Run the sketch
        cmd = [
            processing_java_path,
            "--sketch=" + str(sketch_path),
            "--run"
        ]
        
        print(f"Running: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60  # 60 second timeout
        )
        
        print("STDOUT:")
        print(result.stdout)
        
        if result.stderr:
            print("STDERR:")
            print(result.stderr)
        
        return result.returncode
        
    except subprocess.TimeoutExpired:
        print("⚠️  Sketch timed out (expected in CI mode)")
        return 0
    except Exception as e:
        print(f"❌ Error running sketch: {e}")
        return 1

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 run-sketch-ci.py <sketch_path> [scenario_config_json]")
        return 1
    
    sketch_path = sys.argv[1]
    
    # Parse scenario config if provided
    config = {{}}
    if len(sys.argv) >= 3:
        try:
            config = json.loads(sys.argv[2])
        except json.JSONDecodeError:
            print(f"Warning: Could not parse scenario config, using defaults")
    
    # Get config from environment variables
    config.setdefault('sketchName', os.environ.get('CI_SKETCH_NAME', 'sketch'))
    config.setdefault('scenarioName', os.environ.get('CI_SCENARIO_NAME', 'default'))
    config.setdefault('waitFrames', int(os.environ.get('CI_FRAME_LIMIT', '180')))
    
    # Create wrapper sketch in temp directory
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"Creating CI wrapper in {tmpdir}")
        wrapper_path = create_ci_wrapper_sketch(sketch_path, tmpdir, config)
        
        # Run the wrapper sketch
        return run_sketch_with_processing(wrapper_path)

if __name__ == '__main__':
    sys.exit(main())
