# Processing Sketch CI Testing

This directory contains CI testing infrastructure for Processing sketches, enabling automated builds, headless execution, and screenshot captures in GitHub Actions.

## Overview

The CI system:
- **Discovers sketches automatically** from `examples/` and `src/` directories
- **Builds and validates** all sketches in parallel
- **Runs headless** using Xvfb (virtual framebuffer)
- **Captures screenshots** at specific frames for visual validation
- **No sketch modification required** - uses wrapper approach
- **Uploads artifacts** containing screenshots and test reports

## Files

```
processing-vj/
├── ci-test-config.json              # Test scenarios configuration
├── library-dependencies.json        # Library requirements per sketch
├── discover-sketches.py             # Auto-discover sketches
├── run-sketch-ci.py                 # CI test runner wrapper
├── install-processing-libraries.sh  # Install required libraries
└── examples/, src/                  # Sketch directories
```

## Quick Start

### Running Locally

1. **Install Processing libraries:**
   ```bash
   ./install-processing-libraries.sh
   ```

2. **Test a single sketch in CI mode:**
   ```bash
   export CI_TEST_MODE=true
   export CI_FRAME_LIMIT=120
   export CI_SCREENSHOT_FRAME=100
   export CI_OUTPUT_DIR=./ci-output
   export CI_SKETCH_NAME=WhackAMole
   export CI_SCENARIO_NAME=initial-state
   
   python3 run-sketch-ci.py examples/WhackAMole
   ```

3. **Discover all sketches:**
   ```bash
   python3 discover-sketches.py
   ```

### In GitHub Actions

The CI runs automatically on push/PR to:
- `.github/workflows/processing-sketch-ci.yml`
- `processing-vj/**`

Manual trigger: Go to Actions → "Processing Sketch CI" → Run workflow

## Configuration

### Test Scenarios (`ci-test-config.json`)

Each sketch can have multiple test scenarios:

```json
{
  "sketches": [
    {
      "name": "WhackAMole",
      "path": "processing-vj/examples/WhackAMole",
      "mainFile": "WhackAMole.pde",
      "testScenarios": [
        {
          "name": "initial-state",
          "description": "Capture initial game state",
          "waitFrames": 60,
          "keyInputs": [],
          "screenshotName": "whackamole-initial.png"
        },
        {
          "name": "after-interaction",
          "description": "Simulate interaction",
          "waitFrames": 120,
          "keyInputs": ["MOUSE_CLICK", "r"],
          "screenshotName": "whackamole-interaction.png"
        }
      ]
    }
  ]
}
```

**Scenario fields:**
- `name` - Unique scenario identifier
- `description` - Human-readable description
- `waitFrames` - Number of frames to run before exit
- `keyInputs` - Array of keyboard inputs (not yet implemented)
- `screenshotName` - Output screenshot filename

### Library Dependencies (`library-dependencies.json`)

Defines required Processing libraries:

```json
{
  "libraries": [
    {
      "name": "themidibus",
      "downloadUrl": "https://github.com/sparks/themidibus/...",
      "requiredBy": ["WhackAMole", "BuildupRelease", ...]
    }
  ]
}
```

## How It Works

### 1. Discovery Phase

The `discover` job parses `ci-test-config.json` and creates a matrix of sketches to test.

### 2. Build Phase

For each sketch in parallel:
1. Install Java 17
2. Download and cache Processing 4.3
3. Install required libraries (cached)
4. Build the sketch with `processing-java --build`

### 3. Test Phase

For each test scenario:
1. Start Xvfb (virtual display)
2. Set CI environment variables
3. Run sketch with `run-sketch-ci.py` wrapper
4. Wrapper injects CI test code that:
   - Sets deterministic random seeds
   - Captures screenshot at specified frame
   - Exits after frame limit
5. Screenshot saved to `ci-output/{sketch}/{scenario}.png`

### 4. Artifact Upload

All screenshots and logs uploaded as:
- `processing-screenshots-{SketchName}.zip`
- Retained for 30 days
- Downloadable from workflow run page

## CI Environment Variables

The test runner recognizes these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CI_TEST_MODE` | `false` | Enable CI testing mode |
| `CI_FRAME_LIMIT` | `180` | Exit after N frames |
| `CI_SCREENSHOT_FRAME` | `60` | Capture screenshot at frame N |
| `CI_OUTPUT_DIR` | `ci-output` | Output directory for screenshots |
| `CI_SKETCH_NAME` | `sketch` | Name of the sketch being tested |
| `CI_SCENARIO_NAME` | `default` | Name of the test scenario |

## Adding New Sketches

1. Create your sketch in `examples/` or `src/`
2. Follow the standard Processing structure:
   - Folder name matches main `.pde` file
   - Contains `void setup()` and `void draw()`
3. Run discovery to auto-add to config:
   ```bash
   python3 discover-sketches.py --update
   ```
4. (Optional) Edit `ci-test-config.json` to add custom test scenarios
5. Commit and push - CI will automatically test your sketch

## Adding Test Scenarios

Edit `ci-test-config.json` to add scenarios for a sketch:

```json
{
  "name": "my-scenario",
  "description": "What this scenario tests",
  "waitFrames": 120,
  "keyInputs": [],
  "screenshotName": "my-sketch-scenario.png"
}
```

Scenarios can test:
- Initial state (no interaction)
- After specific number of frames (animation progression)
- After keyboard input (future enhancement)
- Edge cases or specific visual states

## Performance Optimizations

The CI workflow is optimized for speed:

1. **Parallel execution** - All sketches tested simultaneously via matrix strategy
2. **Caching** - Processing installation and libraries cached across runs
3. **fail-fast: false** - Continue testing even if one sketch fails
4. **Targeted builds** - Only runs when Processing files change

## Library Management

### Included Libraries

- **themidibus** - MIDI I/O for Launchpad control
- **oscP5** - OSC communication (includes netP5)
- **processing.sound** - Built-in audio analysis library
- **Syphon** - macOS-only frame sharing (stubbed for Linux)

### Adding New Libraries

1. Update `library-dependencies.json`:
   ```json
   {
     "name": "newlib",
     "downloadUrl": "https://...",
     "requiredBy": ["SketchName"]
   }
   ```

2. Update workflow to install the library in the "Install Processing libraries" step

3. Update `install-processing-libraries.sh` for local development

## Troubleshooting

### Sketch fails to build

- Check library dependencies in sketch imports
- Verify library is installed in workflow
- Check build logs in Actions output

### Screenshot not captured

- Increase `waitFrames` to give sketch more time
- Check `CI_SCREENSHOT_FRAME` < `CI_FRAME_LIMIT`
- Verify sketch reaches the screenshot frame

### Sketch times out

- Default timeout is 60 seconds
- Reduce `waitFrames` in scenario config
- Check for infinite loops in sketch

### Library not found

- Add to `library-dependencies.json`
- Update workflow installation step
- Clear GitHub Actions cache and re-run

## Viewing Results

After workflow completes:

1. Go to workflow run page
2. Scroll to "Artifacts" section
3. Download `processing-screenshots-{SketchName}.zip`
4. Extract to view screenshots and logs
5. Read `TEST_REPORT.md` for scenario details

## Future Enhancements

Planned features:
- [ ] Keyboard/mouse input simulation with xdotool
- [ ] Video recording of sketch execution
- [ ] Performance metrics (frame rate, memory)
- [ ] Visual regression testing (optional)
- [ ] Multi-platform testing (Windows, macOS)

## Related Files

- `.github/workflows/processing-sketch-ci.yml` - Main CI workflow
- `.github/workflows/processing-tests.yml` - Existing validation workflow
- `processing-vj/README.md` - Main Processing VJ documentation
