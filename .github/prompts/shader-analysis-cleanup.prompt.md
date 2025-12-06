---
description: Analyze shader analysis errors and clean up for re-analysis
---

# Shader Analysis Cleanup

Analyze shader analysis errors and optionally clean them up for re-processing.

## Steps

1. **Collect Statistics**
   Run `make stats` to see the current state of shader analysis:
   - How many shaders exist (ISF and GLSL)
   - How many are analyzed
   - How many have errors

2. **List Error Files**
   Find all `.error.json` files and summarize the errors:
   - Group by error type (timeout, parse failure, etc.)
   - Show which shaders failed

3. **Summarize Findings**
   Present a summary:
   - Total shaders vs analyzed vs errors
   - Common error patterns
   - Recommendation (retry errors vs full re-analysis)

4. **Cleanup (if requested)**
   If the user wants to retry failed shaders:
   - Run `make clean-errors` to remove error files
   - Or `make clean-all` for full re-analysis

## Example Commands

```bash
# Show stats
make stats

# List error files
find processing-vj/src/VJUniverse/data/shaders -name "*.error.json"

# Read a specific error
cat processing-vj/src/VJUniverse/data/shaders/isf/SomeShader.error.json

# Clean up errors only
make clean-errors

# Clean everything
make clean-all
```
