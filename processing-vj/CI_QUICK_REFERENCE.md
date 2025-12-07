# Processing CI Quick Reference

## 🚀 Quick Commands

```bash
# Discover all sketches
python3 discover-sketches.py

# Install libraries locally
./install-processing-libraries.sh

# Test a sketch locally (with Processing installed)
export CI_TEST_MODE=true
export CI_SKETCH_NAME=WhackAMole
export CI_SCENARIO_NAME=initial-state
export CI_FRAME_LIMIT=60
python3 run-sketch-ci.py examples/WhackAMole
```

## 📁 Key Files

| File | Purpose |
|------|---------|
| `ci-test-config.json` | Test scenarios for each sketch |
| `library-dependencies.json` | Required Processing libraries |
| `discover-sketches.py` | Auto-discover sketches |
| `run-sketch-ci.py` | CI test runner (wrapper) |
| `install-processing-libraries.sh` | Install libs locally |
| `CI_TESTING.md` | Full documentation |

## 🔧 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CI_TEST_MODE` | `false` | Enable CI mode |
| `CI_FRAME_LIMIT` | `180` | Frames before exit |
| `CI_SCREENSHOT_FRAME` | `60` | Screenshot frame |
| `CI_OUTPUT_DIR` | `ci-output` | Output directory |
| `CI_SKETCH_NAME` | `sketch` | Sketch name |
| `CI_SCENARIO_NAME` | `default` | Scenario name |

## 📸 Viewing Screenshots

1. Go to Actions tab in GitHub
2. Click on a workflow run
3. Scroll to "Artifacts" section
4. Download `processing-screenshots-{SketchName}.zip`
5. Extract and view `TEST_REPORT.md`

## ➕ Adding a New Sketch

1. Create sketch in `examples/` or `src/`
2. Run: `python3 discover-sketches.py --update`
3. (Optional) Edit `ci-test-config.json` for custom scenarios
4. Commit and push - CI runs automatically

## 🔍 Adding Test Scenarios

Edit `ci-test-config.json`:

```json
{
  "name": "my-test",
  "description": "What this tests",
  "waitFrames": 120,
  "keyInputs": [],
  "screenshotName": "sketch-test.png"
}
```

## 📚 Libraries Installed

- **oscP5** - OSC communication (includes netP5)
- **themidibus** - MIDI I/O
- **processing.sound** - Audio analysis (built-in)
- **Syphon** - Frame sharing (macOS-only, stubbed for CI)

## 🐛 Common Issues

**Build fails**: Check library dependencies
**No screenshot**: Increase `waitFrames`
**Timeout**: Reduce `waitFrames` or check for infinite loops

See `CI_TESTING.md` for detailed troubleshooting.

## 🎯 CI Pipeline Features

✅ Parallel execution (all sketches tested simultaneously)  
✅ Caching (Processing + libraries cached)  
✅ No sketch modifications (wrapper approach)  
✅ Screenshot artifacts (30-day retention)  
✅ Deterministic rendering (fixed random seeds)  
✅ Auto-exit after frame limit  

## 📊 Performance

- **Build time**: ~2-3 minutes (first run)
- **Build time**: ~30-60 seconds (cached)
- **Per-sketch**: ~10-30 seconds
- **Total time**: Depends on slowest sketch (parallel)

## 🔗 Related Documentation

- `CI_TESTING.md` - Complete guide
- `library-dependencies.json` - Library info
- `.github/workflows/processing-sketch-ci.yml` - Workflow file
