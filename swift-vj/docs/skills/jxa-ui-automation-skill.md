# JXA UI Automation Skill for SwiftVJApp

## Overview

JavaScript for Automation (JXA) is macOS's built-in scripting bridge for controlling apps via the Accessibility API. It's the best approach for automating SwiftVJApp since the project is SPM-only (no `.xcodeproj` for XCUITest).

Use this document as a reference when you need to:
- Automate UI interactions with SwiftVJApp
- Write end-to-end test scripts that drive the GUI
- Script repetitive workflows (loading boards, searching libraries, taking screenshots)

---

## Quick Start

```javascript
// Run with: osascript -l JavaScript script.js
const se = Application("System Events");
const proc = se.processes.byName("SwiftVJApp");
proc.frontmost = true;
delay(0.5);
const win = proc.windows[0];
```

---

## App UI Hierarchy

### Sidebar (Tab Navigation)

The sidebar contains tabs accessible via outline rows:

```javascript
const sidebar = win.groups[0].groups[0].splitterGroups[0].groups[0];
const outline = sidebar.scrollAreas[0].outlines[0];
// Click Moodboard tab:
outline.rows[9].uiElements[0].click(); // Index may vary
```

Known sidebar tabs (in order):

| Index | Tab             |
|-------|-----------------|
| 0     | Master          |
| 1     | OSC Debug       |
| 2     | Shader Browser  |
| 3     | Performance     |
| 4     | Lyrics          |
| 5     | Songs           |
| 6     | AI Module       |
| 7     | Shaders         |
| 8     | Pipeline        |
| 9     | Moodboard       |
| 10    | Settings        |
| 11    | Audio           |

> **Note:** Tab indices may shift when tabs are added or removed. Verify by inspecting `outline.rows` at runtime.

### Moodboard Content Area

After selecting the Moodboard tab:

```javascript
const content = win.groups[0].groups[0].groups[0];
```

Content children (by index):

| Index  | Element      | Description                                        |
|--------|--------------|----------------------------------------------------|
| `[0]`  | staticText   | Board title ("Untitled Board" or saved name)       |
| `[1]`  | button       | "Add Tag" (no accessibility label — use index)     |
| `[2]`  | button       | help="New empty board"                             |
| `[3]`  | button       | help="Save board"                                  |
| `[4]`  | button       | help="Load board"                                  |
| `[5]`  | button       | help="Toggle library"                              |
| `[6]`  | button       | help="Toggle tag manager"                          |
| `[7-8]`| buttons      | Transport controls (stop/play)                     |
| `[9]`  | staticText   | Preview label ("No preview" or song name)          |
| `[10]` | staticText   | Time display ("0:00 / 0:00")                       |
| `[11-13]` | controls  | Start time controls                                |
| `[14-23]` | buttons/images | Phase flow bar buttons + images               |
| `[24]` | splitterGroup | Main HSplitView                                   |

### HSplitView (Library + Canvas)

```javascript
const split = content.splitterGroups[0];
const lib = split.groups[0];                          // Library panel
const canvas = split.groups[split.groups.length - 1]; // Canvas (always last)
// When the tag manager is open, split.groups has 3 children
```

### Library Panel Structure

```javascript
const lib = split.groups[0];
// lib children:
// [0] staticText "Library"
// [1] button — open folder
// [2] button — clear library
// [3] image
// [4] textField — search field
// [5] scrollArea — phase filter chips (6 buttons, but NO accessibility labels!)
// [6] scrollArea — song list outline
// [7] button — "Add All Filtered (N)"
```

### Song List

```javascript
const outline = lib.scrollAreas[1].outlines[0];
const rowCount = outline.rows.length;
// Each row has uiElements[0] with nested buttons
// "+" button to add song to canvas
// Checkmark appears when song is already on canvas
```

---

## Common Operations

### Find a Button by Help Text

Many SwiftUI buttons have `null` titles. Use the `.help()` property (tooltip) instead:

```javascript
function findButtonByHelp(container, helpText) {
    const btns = container.buttons();
    for (let i = 0; i < btns.length; i++) {
        try {
            if (btns[i].help() === helpText) return btns[i];
        } catch (e) {}
    }
    return null;
}

// Usage:
const saveBtn = findButtonByHelp(content, "Save board");
saveBtn.click();
```

### Type Text into a SwiftUI Text Field

**CRITICAL**: Setting `.value` via the Accessibility API does **NOT** trigger SwiftUI's `@State` binding. You **must** use keystrokes:

1. Click the field to focus it
2. Select all existing text (`Cmd+A`)
3. Type with `se.keystroke()`

```javascript
const searchField = lib.textFields[0];
searchField.click();
delay(0.2);
se.keystroke("a", { using: "command down" }); // select all
se.keystroke("search term");
```

### Clear a Text Field

```javascript
searchField.click();
delay(0.2);
se.keystroke("a", { using: "command down" });
se.keyCode(51); // Delete key
```

### Take Screenshots

```javascript
function screenshot(name) {
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    app.doShellScript("screencapture -x ~/Desktop/" + name + ".png");
}
```

### Open a Music Folder via NSOpenPanel

```javascript
// Click the open folder button
lib.buttons[0].click(); // or find by position
delay(1.0);

// NSOpenPanel navigation:
se.keystroke("g", { using: ["command down", "shift down"] }); // Go to folder
delay(0.5);
se.keystroke("/path/to/music/folder");
delay(0.3);
se.keyCode(36); // Enter (go to path)
delay(0.5);
se.keyCode(36); // Enter (open folder)
```

### Save a Board

```javascript
findButtonByHelp(content, "Save board").click();
delay(0.5);
const sheet = win.sheets[0]; // Save dialog is a sheet
const tf = sheet.textFields[0];
tf.click();
delay(0.2);
se.keystroke("a", { using: "command down" });
se.keystroke("My Board Name");
se.keyCode(36); // Enter to save
```

### Load a Board

```javascript
findButtonByHelp(content, "Load board").click();
delay(0.5);
const sheet = win.sheets[0];
const outline = sheet.groups[0].scrollAreas[0].outlines[0];
// Each row: title, node count, duration, Load button, Delete button
const loadBtn = outline.rows[0].uiElements[0].buttons[0]; // "Load" button
loadBtn.click();
```

---

## Keyboard Shortcuts

```javascript
se.keystroke("a", { using: "command down" });     // Select all
se.keyCode(51);                                    // Delete selected
se.keystroke("z", { using: "command down" });     // Undo
se.keystroke("=", { using: "command down" });     // Zoom in
se.keystroke("-", { using: "command down" });     // Zoom out
se.keystroke("0", { using: "command down" });     // Reset zoom
se.keyCode(49);                                    // Space — play preview
se.keyCode(49, { using: "shift down" });          // Shift+Space — stop preview
se.keyCode(53);                                    // Escape — cancel/close
```

---

## Key Codes Reference

| Key              | Code |
|------------------|------|
| Return / Enter   | 36   |
| Tab              | 48   |
| Space            | 49   |
| Delete/Backspace | 51   |
| Escape           | 53   |
| Left Arrow       | 123  |
| Right Arrow      | 124  |
| Down Arrow       | 125  |
| Up Arrow         | 126  |

---

## Known Limitations

### Things you **cannot** do via the JXA Accessibility API

1. **Drag nodes** — SwiftUI `DragGesture` requires continuous mouse events (press, move, release). JXA can only `.click()`.
2. **Draw edges** — Requires a drag from one node handle to another at pixel-precise coordinates.
3. **Pinch to zoom** — Only keyboard zoom (`Cmd+=` / `Cmd+-`) works.
4. **Coordinate-based clicks** — `se.click({ at: [x, y] })` throws "Can't convert types" on SwiftUI views. Only `.click()` on AX elements works.

### SwiftUI-specific quirks

1. **Text field binding** — `.value = "text"` does **not** update SwiftUI `@State`. Must use `keystroke()`.
2. **Segmented controls** — Clicking radio buttons in SwiftUI `Picker(style: .segmented)` is unreliable — animation timing causes the wrong selection.
3. **Popovers** — SwiftUI `.popover()` content appears inline in the AX hierarchy, not as separate AX popover elements.
4. **`entireContents()`** — **Extremely slow** (30–60s) on complex views. **Never use it.** Navigate the hierarchy directly.
5. **Null titles** — Many SwiftUI buttons have `null` title in AX. Use `.help()` tooltips or positional indexing.

### Workarounds

| Problem                | Workaround                                                                 |
|------------------------|----------------------------------------------------------------------------|
| Drag operations        | Use `CGEvent` via Python (`import Quartz`) or install `cliclick` for coordinate-based mouse control. |
| Element identification | Add `.accessibilityLabel()` and `.accessibilityIdentifier()` to SwiftUI views. |
| Slow hierarchy walk    | Navigate to elements by known index paths instead of using `entireContents()`. |

---

## Testing Pattern

```javascript
const results = [];

function log(test, status, detail) {
    results.push({ test, status, detail });
    console.log("[" + status + "] " + test + ": " + detail);
}

function safeGet(fn, fallback) {
    try {
        return fn();
    } catch (e) {
        return fallback;
    }
}

// Run a test
try {
    // ... test code ...
    log("Test Name", "PASS", "details");
} catch (e) {
    log("Test Name", "ERROR", e.message);
}

// Summary
let pass = 0, fail = 0;
results.forEach(function (r) {
    if (r.status === "PASS") pass++;
    else fail++;
});
console.log("PASS: " + pass + "  FAIL: " + fail);
```

---

## Running Scripts

```bash
# Run a JXA script file
osascript -l JavaScript script.js

# One-liner
osascript -l JavaScript -e 'Application("System Events").processes.byName("SwiftVJApp").windows[0].title()'

# With error output
osascript -l JavaScript script.js 2>&1
```

---

## Debugging Tips

### Inspect the AX hierarchy interactively

```bash
# Launch a JXA REPL
osascript -l JavaScript -i
```

Then explore step by step:

```javascript
const se = Application("System Events");
const proc = se.processes.byName("SwiftVJApp");
const win = proc.windows[0];

// List direct children of a group
const g = win.groups[0];
g.uiElements().map(function (el) {
    return el.role() + " / " + el.title();
});
```

### Useful AX properties

```javascript
element.role()            // "AXButton", "AXStaticText", etc.
element.title()           // Accessibility title (often null in SwiftUI)
element.help()            // Tooltip / help text
element.value()           // Current value (text fields, sliders)
element.description()     // AX description
element.enabled()         // Whether the element is interactive
element.focused()         // Whether the element has keyboard focus
element.position()        // [x, y] screen position
element.size()            // [w, h] dimensions
element.uiElements()      // Direct children
element.buttons()         // Child buttons
element.textFields()      // Child text fields
element.staticTexts()     // Child static text elements
```

### Print a shallow hierarchy map

```javascript
function mapChildren(container, depth) {
    depth = depth || 0;
    const indent = "  ".repeat(depth);
    const els = container.uiElements();
    for (let i = 0; i < els.length; i++) {
        const el = els[i];
        try {
            const role = el.role();
            const title = el.title() || "";
            const help = el.help() || "";
            console.log(indent + "[" + i + "] " + role + " title=" + JSON.stringify(title) + " help=" + JSON.stringify(help));
        } catch (e) {
            console.log(indent + "[" + i + "] (error: " + e.message + ")");
        }
    }
}

mapChildren(content); // one level deep — fast and safe
```
