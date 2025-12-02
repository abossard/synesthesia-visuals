# VDJScript Reference Guide

A concise reference for AI agents and developers working with VirtualDJ's scripting language.

## Overview

VDJScript is VirtualDJ's built-in scripting language for controlling DJ software through custom mappings, automation, and external APIs. It's designed for controller mapping, button actions, and the Network Control HTTP API.

## Core Concepts

### Actions vs Queries

- **Action**: Executes a command (e.g., `play` starts playback)
- **Query**: Returns information (e.g., `get_title` returns song title)
- Context determines behavior: Same verb can be action (button) or query (LED/API)

### Deck Selection

Always specify which deck to target:

```vdjscript
deck 1 play                    # Deck 1
deck 2 volume 50%              # Deck 2
deck left get_title            # Left deck
deck right pause               # Right deck
masterdeck get_bpm             # Currently active masterdeck
```

**Deck identifiers**: `1`, `2`, `3`, `4`, `left`, `right`, `leftvideo`, `rightvideo`, `master`, `active`, `default`

## Syntax Elements

### Basic Command Structure

```vdjscript
[deck N] verb [parameters]
```

### Chaining Commands

Use `&` to chain multiple commands:

```vdjscript
play & loop 4 & effect_active 'echo'
deck 1 play & deck 2 pause
```

### Conditional Logic (Ternary)

```vdjscript
condition ? action_if_true : action_if_false
```

Examples:
```vdjscript
play ? pause : play                           # Toggle play/pause
get_bpm >= 128 ? show_text "Fast" : show_text "Slow"
deck 1 play ? deck 2 sync : nothing
```

### Nested Conditions

```vdjscript
play ? (get_bpm > 120 ? effect_active 'flanger' : loop 4) : play
```

### While Pressed Actions

```vdjscript
volume 100% while_pressed      # Only while button held
```

### Variables

```vdjscript
set '$counter' 5               # Set global variable
set '$deck_var' 42             # Set deck-specific variable
get_var '$counter'             # Retrieve variable value
```

### String Embedding

Use backticks to embed query results in text:

```vdjscript
show_text "Now: `get_title` by `get_artist`"
show_text "BPM: `get_bpm` Position: `get_position`"
```

## Common Query Verbs (for Network Control API)

### Track Information

| Verb | Returns | Example |
|------|---------|---------|
| `get_title` | Track title | `deck 1 get_title` |
| `get_artist` | Artist name | `deck 2 get_artist` |
| `get_bpm` | Beats per minute | `masterdeck get_bpm` |
| `get_songlength` | Total duration in seconds | `deck 1 get_songlength` |
| `get_position` | Position as 0.0-1.0 | `deck 1 get_position` |
| `get_time` | Remaining time in seconds | `deck 1 get_time` |
| `get_time "elapsed"` | Elapsed time in seconds | `deck 1 get_time "elapsed"` |

### Playback State

| Verb | Returns | Example |
|------|---------|---------|
| `play` | 1 if playing, 0 if paused | `deck 1 play` |
| `pause` | 1 if paused, 0 if playing | `deck 1 pause` |
| `masterdeck` | 1 if masterdeck, 0 if not | `deck 1 masterdeck ? 1 : 0` |

### Deck Control

| Verb | Action | Example |
|------|--------|---------|
| `play` | Start/resume playback | `deck 1 play` |
| `pause` | Pause playback | `deck 2 pause` |
| `stop` | Stop and reset to start | `deck 1 stop` |
| `sync` | Sync to masterdeck BPM | `deck 2 sync` |
| `load` | Load track | `deck 1 load "path/to/song.mp3"` |

## Network Control HTTP API Usage

### Query Endpoint (GET Information)

**POST to**: `http://127.0.0.1:8080/query`  
**Content-Type**: `text/plain; charset=utf-8`  
**Body**: VDJScript command

Examples:
```bash
# Get deck 1 title
POST http://127.0.0.1:8080/query
Body: deck 1 get_title

# Get masterdeck BPM
POST http://127.0.0.1:8080/query
Body: masterdeck get_bpm

# Get position (0-1)
POST http://127.0.0.1:8080/query
Body: deck 2 get_position

# Check if deck is masterdeck
POST http://127.0.0.1:8080/query
Body: deck 1 masterdeck ? 1 : 0
```

### Execute Endpoint (Perform Actions)

**POST to**: `http://127.0.0.1:8080/execute`  
**Content-Type**: `text/plain; charset=utf-8`  
**Body**: VDJScript command

Examples:
```bash
# Play deck 1
POST http://127.0.0.1:8080/execute
Body: deck 1 play

# Set volume
POST http://127.0.0.1:8080/execute
Body: deck 2 volume 75%
```

### Authentication

If password is set in VirtualDJ Network Control plugin:

**Query parameter method**:
```
POST http://127.0.0.1:8080/query?bearer=mypassword
```

**Header method**:
```
Authorization: Bearer mypassword
```

## Best Practices

### 1. Always Specify Deck

```vdjscript
# Good
deck 1 get_title

# Ambiguous (uses default/active deck)
get_title
```

### 2. Use Masterdeck for Active Deck

```vdjscript
# Query currently active deck
masterdeck get_bpm
masterdeck get_title
```

### 3. Handle Missing Data

Queries return empty strings for missing data. Always provide defaults:

```python
# Python example
bpm_str = client.query("deck 1 get_bpm")
bpm = float(bpm_str) if bpm_str else 0.0
```

### 4. Quote String Parameters

```vdjscript
# Correct
get_time "elapsed"
effect_active 'flanger'

# Wrong
get_time elapsed  # May not work
```

### 5. Format Output for Display

Use parameter casting:

```vdjscript
get_bpm & param_cast "000"           # BPM as 3 digits: 128
get_position & param_cast "percentage"  # Position as %: 45%
```

### 6. Keep Queries Simple

For API calls, use single-purpose queries:

```vdjscript
# Good - one query
deck 1 get_title

# Avoid - multiple unrelated queries
deck 1 get_title & deck 2 get_artist
```

### 7. Poll Rate Considerations

- For position tracking: Poll every 0.5-2 seconds
- For metadata: Poll when track changes
- Avoid excessive polling (VDJ has built-in rate limiting)

## Common Patterns

### Track Change Detection

```python
# Poll masterdeck, compare artist/title
last_track = ""
while True:
    title = query("masterdeck get_title")
    artist = query("masterdeck get_artist")
    track_key = f"{artist}::{title}"
    
    if track_key != last_track:
        last_track = track_key
        print(f"Track changed: {artist} - {title}")
    
    time.sleep(1)
```

### Masterdeck Detection

```python
# Check which deck is masterdeck
for deck in [1, 2]:
    result = query(f"deck {deck} masterdeck ? 1 : 0")
    if result == "1":
        print(f"Deck {deck} is masterdeck")
```

### Get Full Track Status

```python
deck = 1
status = {
    'title': query(f"deck {deck} get_title"),
    'artist': query(f"deck {deck} get_artist"),
    'bpm': float(query(f"deck {deck} get_bpm") or 0),
    'position': float(query(f"deck {deck} get_position") or 0),
    'elapsed_ms': int(query(f"deck {deck} get_time 'elapsed'") or 0),
    'length_sec': float(query(f"deck {deck} get_songlength") or 0),
}
```

### Time Conversion

```python
# Convert position (0-1) to elapsed time
position = float(query("deck 1 get_position"))
length_sec = float(query("deck 1 get_songlength"))
elapsed_sec = position * length_sec
```

## Common Gotchas

### 1. Empty String Returns

Queries return empty strings when:
- No track loaded
- Data not available
- Deck doesn't exist

Always handle empty returns:
```python
bpm = query("deck 1 get_bpm")
bpm_value = float(bpm) if bpm else 0.0
```

### 2. Number Formatting

VDJ may return numbers with commas as decimal separators in some locales:
```python
bpm_str = "128,5"  # Some locales
bpm = float(bpm_str.replace(",", "."))
```

### 3. Elapsed Time Syntax

Must quote "elapsed":
```vdjscript
# Correct
get_time "elapsed"

# May not work
get_time elapsed
```

### 4. Masterdeck Query

Masterdeck check needs ternary:
```vdjscript
# Correct
deck 1 masterdeck ? 1 : 0

# Wrong - this is an action, not a query
deck 1 masterdeck
```

### 5. Position vs Time

- `get_position`: Returns 0.0-1.0 (percentage through track)
- `get_time`: Returns seconds remaining
- `get_time "elapsed"`: Returns seconds elapsed

Don't confuse these!

## Error Handling

### Connection Errors

```python
import requests

def query(script):
    try:
        response = requests.post(
            "http://127.0.0.1:8080/query",
            data=script.encode('utf-8'),
            headers={'Content-Type': 'text/plain; charset=utf-8'},
            timeout=2.0
        )
        response.raise_for_status()
        return response.text.strip()
    except requests.RequestException:
        return None  # VDJ not running or network error
```

### Invalid Verbs

Invalid verbs return empty strings. Check results:
```python
result = query("deck 1 invalid_verb")
if not result:
    print("Empty result - verb invalid or no data")
```

## Resources

- **Official Verb List**: [VirtualDJ Manual - VDJScript Verbs](https://www.virtualdj.com/manuals/virtualdj/appendix/vdjscriptverbs.html)
- **Syntax Guide**: [VDJPedia - VDJScript](https://www.virtualdj.com/wiki/VDJscript.html)
- **Examples**: [VDJPedia - VDJScript Examples](https://www.virtualdj.com/wiki/VDJScript%20Examples.html)
- **Network Control**: [VDJPedia - NetworkControlPlugin](https://www.virtualdj.com/wiki/NetworkControlPlugin.html)

## Quick Reference Card

```vdjscript
# Deck Selection
deck 1|2|3|4|left|right|master|active [verb]

# Chaining
verb1 & verb2 & verb3

# Conditional
condition ? true_action : false_action

# Variables
set '$name' value
get_var '$name'

# String Embedding
show_text "`get_title` - `get_artist`"

# Essential Queries
get_title         # Track title
get_artist        # Artist name
get_bpm           # BPM
get_position      # 0.0-1.0 position
get_songlength    # Total seconds
get_time          # Remaining seconds
get_time "elapsed"  # Elapsed seconds

# Masterdeck Detection
deck N masterdeck ? 1 : 0

# HTTP API
POST /query   - Get information (query verbs)
POST /execute - Perform actions (action verbs)
```

## Summary

VDJScript is a simple but powerful language for VirtualDJ control. Key points:

1. **Deck-specific**: Always specify which deck
2. **Dual nature**: Same verb = action or query depending on context
3. **Simple syntax**: Chaining with `&`, conditionals with `? :`
4. **HTTP API**: POST text/plain to `/query` or `/execute`
5. **Handle empties**: Queries return empty strings when no data
6. **Quote strings**: Use quotes for string parameters like `"elapsed"`

This reference should provide everything needed for AI agents to generate correct VDJScript commands for automation, monitoring, and control tasks.
