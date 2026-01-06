# VJ Console UI Guide

This document provides an overview of each screen in the VJ Console terminal UI.

## Quick Navigation

| Key | Screen |
|-----|--------|
| 1 | Master Control |
| 2 | OSC View |
| 3 | Song AI Debug |
| 4 | All Logs |
| 6 | Launchpad Controller |
| 7 | Shader Index |
| q | Quit |

---

## Master Control (Press 1)

The main dashboard showing all key information at a glance.

**Left Column:**
- **Startup Control** - Start/stop all services, configure auto-start
- **Playback Source** - Select music source (Spotify, VirtualDJ, etc.)
- **Master Control** - Quick controls for timing adjustment
- **Apps List** - Processing apps status and controls
- **Services** - External service health (LM Studio, etc.)

**Right Column:**
- **Now Playing** - Current track info with progress
- **Categories** - AI-detected song categories (mood, genre, era)
- **Pipeline** - Processing pipeline status

![Master Control](tests/e2e/screenshots/01_master_control.svg)

---

## OSC View (Press 2)

Full OSC message debugging view.

- **OSC Control Panel** - Start/stop individual channels or all at once
- **Message Log** - Live stream of all OSC messages grouped by address
- Shows message frequency, last values, and timestamps
- Useful for debugging communication with Synesthesia, VirtualDJ, etc.

![OSC View](tests/e2e/screenshots/02_osc_view.svg)

---

## Song AI Debug (Press 3)

Detailed view of song categorization and AI analysis.

**Left Column:**
- **Categories** - Full breakdown of detected categories with confidence scores

**Right Column:**
- **Pipeline** - Detailed processing pipeline with timing for each step

![Song AI Debug](tests/e2e/screenshots/03_ai_debug.svg)

---

## All Logs (Press 4)

Complete application log output.

- Shows INFO, WARNING, and ERROR level messages
- Timestamps and source module for each entry
- Scrollable history
- Useful for debugging issues

![All Logs](tests/e2e/screenshots/04_logs.svg)

---

## Launchpad Controller (Press 6)

Launchpad MIDI controller integration.

**Left Column:**
- **Status** - Controller connection status
- **Pads** - Current pad mappings and learn mode status

**Right Column:**
- **Instructions** - How to use the controller
- **Tests** - Test buttons for debugging
- **OSC Debug** - OSC messages sent/received by controller

![Launchpad Controller](tests/e2e/screenshots/05_launchpad.svg)

---

## Shader Index (Press 7)

Shader analysis and matching system.

**Actions:** Pause/Resume analysis, Search by mood/energy, Rescan

**Left Column:**
- **Shader Index** - List of indexed shaders with feature scores
- **Analysis** - Current analysis status and progress

**Right Column:**
- **Search Results** - Matching shaders for current song
- **Match Details** - Why a shader was matched (feature similarity)

![Shader Index](tests/e2e/screenshots/06_shaders.svg)

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| s | Toggle Synesthesia |
| m | Toggle MilkSyphon |
| + | Increase timing offset |
| - | Decrease timing offset |
| p | Pause/Resume shader analysis (on Shaders tab) |
| / | Search shaders by mood (on Shaders tab) |
| e | Search shaders by energy (on Shaders tab) |
| R | Rescan shaders (on Shaders tab) |

---

*Generated from UI screenshots*
