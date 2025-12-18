#!/usr/bin/env python3
"""
Accessibility Investigation Playground

Uses atomacos to explore macOS application UIs via Accessibility API.
Focus: djay Pro (bundle: com.algoriddim.djay-iphone-free)

Requirements:
  - pip install --pre atomacos
  - System Settings → Privacy & Security → Accessibility → enable Terminal/VSCode

Usage:
  python accessibility.py              # Run investigation
  python accessibility.py --list       # List running apps
  python accessibility.py --dump       # Dump full UI hierarchy
  python accessibility.py --hittest    # Use hit-test technique for hidden elements
"""

import json
import sys

try:
    import atomacos
    import AppKit
    import Quartz
    import ApplicationServices
except ImportError:
    print("ERROR: atomacos not installed. Run: pip install --pre atomacos")
    sys.exit(1)


# =============================================================================
# CONSTANTS
# =============================================================================

DJAY_BUNDLE_ID = "com.algoriddim.djay-iphone-free"
DJAY_APP_NAMES = ["djay Pro", "djay Pro AI", "djay"]


# =============================================================================
# LOW-LEVEL ACCESSIBILITY HELPERS
# =============================================================================

def get_app_element_by_pid(pid: int):
    """Create AXUIElement for an application by PID using low-level API."""
    return ApplicationServices.AXUIElementCreateApplication(pid)


def get_element_at_position(x: float, y: float):
    """Use hit-test to find element at screen position (for hidden UI hierarchies)."""
    system_wide = ApplicationServices.AXUIElementCreateSystemWide()
    err, element = ApplicationServices.AXUIElementCopyElementAtPosition(system_wide, x, y, None)
    if err == 0 and element:
        return element
    return None


def get_ax_attribute(element, attribute: str):
    """Get an accessibility attribute value from an element."""
    err, value = ApplicationServices.AXUIElementCopyAttributeValue(element, attribute, None)
    if err == 0:
        return value
    return None


def get_ax_children(element) -> list:
    """Get children of an AX element."""
    children = get_ax_attribute(element, "AXChildren")
    return list(children) if children else []


def get_ax_windows(app_element) -> list:
    """Get windows from app element using low-level API."""
    windows = get_ax_attribute(app_element, "AXWindows")
    return list(windows) if windows else []


def get_ax_info(element) -> dict:
    """Extract info from low-level AXUIElement."""
    info: dict = {}
    attrs = ["AXRole", "AXTitle", "AXDescription", "AXValue", "AXIdentifier", 
             "AXRoleDescription", "AXPosition", "AXSize", "AXEnabled", "AXFocused"]
    for attr in attrs:
        val = get_ax_attribute(element, attr)
        if val is not None:
            # Convert CoreFoundation types
            if hasattr(val, "x") and hasattr(val, "y"):
                val = (val.x, val.y)
            elif hasattr(val, "width") and hasattr(val, "height"):
                val = (val.width, val.height)
            info[attr] = val
    return info


def walk_ax_hierarchy(element, depth: int = 0, max_depth: int = 5) -> list[dict]:
    """Walk low-level AX hierarchy."""
    if depth > max_depth:
        return []
    
    result = []
    info = get_ax_info(element)
    info["depth"] = depth
    result.append(info)
    
    children = get_ax_children(element)
    for child in children:
        result.extend(walk_ax_hierarchy(child, depth + 1, max_depth))
    
    return result


def print_ax_hierarchy(element, depth: int = 0, max_depth: int = 4, indent: str = "  "):
    """Print low-level AX hierarchy."""
    info = get_ax_info(element)
    prefix = indent * depth
    
    role = info.get("AXRole", "?")
    title = info.get("AXTitle") or info.get("AXDescription") or info.get("AXIdentifier") or ""
    value = info.get("AXValue")
    
    display = f"{prefix}[{role}]"
    if title:
        display += f' "{title}"'
    if value and str(value) != str(title):
        val_str = str(value)[:50]
        display += f" = {val_str}"
    
    print(display)
    
    if depth < max_depth:
        children = get_ax_children(element)
        for child in children:
            print_ax_hierarchy(child, depth + 1, max_depth, indent)


# =============================================================================
# HELPERS
# =============================================================================

def list_running_apps() -> list[dict]:
    """List all running applications with accessibility info."""
    workspace = AppKit.NSWorkspace.sharedWorkspace()
    running_apps = workspace.runningApplications()
    result = []
    for app in running_apps:
        name = app.localizedName()
        bundle_id = app.bundleIdentifier()
        if name and bundle_id:  # filter out system processes
            result.append({
                "name": name,
                "bundle_id": bundle_id,
                "pid": app.processIdentifier(),
            })
    return result


def find_djay_app():
    """Find djay Pro in running apps and return NativeUIElement or None."""
    # Try by bundle ID first
    try:
        app = atomacos.getAppRefByBundleId(DJAY_BUNDLE_ID)
        print(f"✓ Found djay Pro by bundle ID: {DJAY_BUNDLE_ID}")
        return app
    except Exception as e:
        print(f"  Bundle ID lookup failed: {e}")
    
    # Fallback: search by app name
    running = list_running_apps()
    for app_info in running:
        name = app_info.get("name", "")
        if name and any(djay_name.lower() in name.lower() for djay_name in DJAY_APP_NAMES):
            try:
                app = atomacos.getAppRefByBundleId(app_info["bundle_id"])
                print(f"✓ Found by name match: {name} ({app_info['bundle_id']})")
                return app
            except Exception:
                try:
                    app = atomacos.getAppRefByPid(app_info["pid"])
                    print(f"✓ Found by PID: {name} (pid={app_info['pid']})")
                    return app
                except Exception:
                    pass
    
    return None


def get_element_info(element) -> dict:
    """Extract key attributes from an accessibility element."""
    info: dict = {"role": None, "title": None, "description": None, "value": None, "position": None, "size": None}
    
    attrs = [
        ("AXRole", "role"),
        ("AXTitle", "title"),
        ("AXDescription", "description"),
        ("AXValue", "value"),
        ("AXRoleDescription", "role_description"),
        ("AXIdentifier", "identifier"),
        ("AXHelp", "help"),
        ("AXPosition", "position"),
        ("AXSize", "size"),
        ("AXEnabled", "enabled"),
        ("AXFocused", "focused"),
    ]
    
    for ax_attr, key in attrs:
        try:
            val = getattr(element, ax_attr, None)
            if val is not None:
                # Convert NSPoint/NSSize to tuple
                if hasattr(val, "x") and hasattr(val, "y"):
                    val = (val.x, val.y)
                elif hasattr(val, "width") and hasattr(val, "height"):
                    val = (val.width, val.height)
                info[key] = val
        except Exception:
            pass
    
    # Get available actions
    try:
        info["actions"] = element.AXActions if hasattr(element, "AXActions") else []
    except Exception:
        info["actions"] = []
    
    return info


def walk_hierarchy(element, depth: int = 0, max_depth: int = 5) -> list[dict]:
    """Recursively walk UI hierarchy and collect element info."""
    if depth > max_depth:
        return []
    
    result = []
    info = get_element_info(element)
    info["depth"] = depth
    result.append(info)
    
    try:
        children = element.AXChildren or []
        for child in children:
            result.extend(walk_hierarchy(child, depth + 1, max_depth))
    except Exception:
        pass
    
    return result


def print_hierarchy(element, depth: int = 0, max_depth: int = 3, indent: str = "  "):
    """Pretty-print UI hierarchy to console."""
    info = get_element_info(element)
    prefix = indent * depth
    
    role = info.get("role", "?")
    title = info.get("title") or info.get("description") or info.get("identifier") or ""
    value = info.get("value")
    
    display = f"{prefix}[{role}]"
    if title:
        display += f' "{title}"'
    if value and value != title:
        display += f" = {value}"
    
    print(display)
    
    if depth < max_depth:
        try:
            children = element.AXChildren or []
            for child in children:
                print_hierarchy(child, depth + 1, max_depth, indent)
        except Exception:
            pass


def find_elements_by_role(element, role: str, max_depth: int = 10) -> list:
    """Find all elements matching a role (e.g., 'AXButton', 'AXSlider')."""
    matches = []
    
    try:
        if getattr(element, "AXRole", None) == role:
            matches.append(element)
    except Exception:
        pass
    
    if max_depth > 0:
        try:
            children = element.AXChildren or []
            for child in children:
                matches.extend(find_elements_by_role(child, role, max_depth - 1))
        except Exception:
            pass
    
    return matches


def find_elements_by_title(element, title_contains: str, max_depth: int = 10) -> list:
    """Find elements whose title contains a string (case-insensitive)."""
    matches = []
    title_lower = title_contains.lower()
    
    try:
        element_title = getattr(element, "AXTitle", None) or getattr(element, "AXDescription", None) or ""
        if title_lower in element_title.lower():
            matches.append(element)
    except Exception:
        pass
    
    if max_depth > 0:
        try:
            children = element.AXChildren or []
            for child in children:
                matches.extend(find_elements_by_title(child, title_contains, max_depth - 1))
        except Exception:
            pass
    
    return matches


# =============================================================================
# DJAY PRO SPECIFIC INVESTIGATION
# =============================================================================

def investigate_djay():
    """Main investigation of djay Pro UI structure."""
    print("\n" + "=" * 60)
    print("DJAY PRO ACCESSIBILITY INVESTIGATION")
    print("=" * 60 + "\n")
    
    # Find djay Pro app info
    djay_info = None
    for app_info in list_running_apps():
        if app_info.get("bundle_id") == DJAY_BUNDLE_ID:
            djay_info = app_info
            break
        if any(name.lower() in (app_info.get("name") or "").lower() for name in DJAY_APP_NAMES):
            djay_info = app_info
            break
    
    if not djay_info:
        print("✗ djay Pro not found! Make sure it's running.")
        print("\nRunning apps with 'dj' in name:")
        for a in list_running_apps():
            if "dj" in (a.get("name") or "").lower():
                print(f"  - {a}")
        return None
    
    print(f"✓ Found: {djay_info['name']} (pid={djay_info['pid']}, bundle={djay_info['bundle_id']})")
    
    # --- Try atomacos first ---
    print("\n--- APPROACH 1: atomacos getAppRefByBundleId ---")
    app = None
    try:
        app = atomacos.getAppRefByBundleId(djay_info["bundle_id"])
        print(f"App reference: {app}")
        windows = app.windows()
        print(f"Found {len(windows)} window(s) via atomacos")
    except Exception as e:
        print(f"atomacos failed: {e}")
        windows = []
    
    # --- Try low-level API ---
    print("\n--- APPROACH 2: Low-level ApplicationServices API ---")
    try:
        ax_app = get_app_element_by_pid(djay_info["pid"])
        ax_windows = get_ax_windows(ax_app)
        print(f"Found {len(ax_windows)} window(s) via low-level API")
        
        if ax_windows:
            print("\n--- WINDOW HIERARCHY (low-level, depth=4) ---")
            for i, win in enumerate(ax_windows):
                win_info = get_ax_info(win)
                print(f"\n[Window {i}] {win_info.get('AXTitle', 'untitled')}")
                print_ax_hierarchy(win, max_depth=4)
    except Exception as e:
        print(f"Low-level API error: {e}")
        ax_windows = []
    
    # --- Hit-test approach for hidden elements ---
    print("\n--- APPROACH 3: Hit-Test (for hidden UI hierarchies) ---")
    print("Trying to probe screen positions where djay Pro window likely is...")
    
    # Get screen dimensions
    main_screen = AppKit.NSScreen.mainScreen()
    screen_frame = main_screen.frame()
    screen_h = screen_frame.size.height
    
    # Try a few positions (center, left-center, right-center)
    test_points = [
        (screen_frame.size.width / 2, screen_h / 2),
        (screen_frame.size.width / 3, screen_h / 2),
        (2 * screen_frame.size.width / 3, screen_h / 2),
        (screen_frame.size.width / 2, screen_h / 3),
    ]
    
    found_djay_elements = []
    for x, y in test_points:
        # Convert to screen coordinates (top-left origin)
        screen_y = screen_h - y  # Flip Y axis
        element = get_element_at_position(x, screen_y)
        if element:
            info = get_ax_info(element)
            app_elem = get_ax_attribute(element, "AXTopLevelUIElement")
            if app_elem:
                app_info = get_ax_info(app_elem)
                app_title = app_info.get("AXTitle", "")
                if "djay" in app_title.lower():
                    print(f"  Hit at ({x:.0f}, {y:.0f}): [{info.get('AXRole')}] {info.get('AXTitle', '')}")
                    found_djay_elements.append(element)
    
    if found_djay_elements:
        print(f"\nFound {len(found_djay_elements)} djay element(s) via hit-test")
        print("\nExploring first hit-test element hierarchy:")
        print_ax_hierarchy(found_djay_elements[0], max_depth=3)
    else:
        print("No djay elements found via hit-test. Window may be offscreen or obscured.")
    
    # --- Use atomacos to explore if we have windows ---
    if windows:
        main_window = windows[0]
        explore_with_atomacos(main_window)
    
    return app


def explore_with_atomacos(main_window):
    """Explore window using atomacos high-level API."""
    print("\n--- UI HIERARCHY (atomacos, depth=3) ---")
    print_hierarchy(main_window, max_depth=3)
    
    print("\n--- SLIDERS (potential faders/EQ) ---")
    sliders = find_elements_by_role(main_window, "AXSlider")
    for s in sliders[:20]:
        info = get_element_info(s)
        print(f"  Slider: {info.get('title') or info.get('description') or 'unnamed'} = {info.get('value')}")
    
    print("\n--- BUTTONS ---")
    buttons = find_elements_by_role(main_window, "AXButton")
    for b in buttons[:30]:
        info = get_element_info(b)
        title = info.get("title") or info.get("description") or info.get("identifier") or "unnamed"
        print(f"  Button: {title}")
    
    print("\n--- STATIC TEXT (labels, track info) ---")
    texts = find_elements_by_role(main_window, "AXStaticText")
    for t in texts[:30]:
        info = get_element_info(t)
        val = info.get("value") or info.get("title") or ""
        if val:
            print(f"  Text: {val[:80]}")
    
    print("\n--- SEARCHING FOR DJ-RELATED ELEMENTS ---")
    keywords = ["deck", "bpm", "tempo", "crossfader", "volume", "play", "cue", "sync", "master"]
    for kw in keywords:
        matches = find_elements_by_title(main_window, kw)
        if matches:
            print(f"  '{kw}': {len(matches)} match(es)")
            for m in matches[:3]:
                info = get_element_info(m)
                print(f"    - [{info.get('role')}] {info.get('title') or info.get('description')}")


def dump_full_hierarchy(app, output_file: str = "djay_ui_dump.json"):
    """Dump complete UI hierarchy to JSON file."""
    # Find djay Pro pid
    djay_info = None
    for app_info in list_running_apps():
        if app_info.get("bundle_id") == DJAY_BUNDLE_ID:
            djay_info = app_info
            break
    
    if not djay_info:
        print("djay Pro not running!")
        return
    
    print(f"Dumping UI for: {djay_info['name']} (pid={djay_info['pid']})")
    
    try:
        ax_app = get_app_element_by_pid(djay_info["pid"])
        ax_windows = get_ax_windows(ax_app)
        
        if not ax_windows:
            print("No windows found via low-level API.")
            # Try atomacos
            try:
                app = atomacos.getAppRefByBundleId(djay_info["bundle_id"])
                windows = app.windows()
                if windows:
                    hierarchy = []
                    for win in windows:
                        hierarchy.extend(walk_hierarchy(win, max_depth=10))
                    with open(output_file, "w") as f:
                        json.dump(hierarchy, f, indent=2, default=str)
                    print(f"✓ Dumped {len(hierarchy)} elements (atomacos) to {output_file}")
                    return
            except Exception as e:
                print(f"atomacos also failed: {e}")
            return
        
        hierarchy = []
        for win in ax_windows:
            hierarchy.extend(walk_ax_hierarchy(win, max_depth=10))
        
        with open(output_file, "w") as f:
            json.dump(hierarchy, f, indent=2, default=str)
        
        print(f"✓ Dumped {len(hierarchy)} elements (low-level API) to {output_file}")
    except Exception as e:
        print(f"Error dumping hierarchy: {e}")


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    if "--list" in sys.argv:
        print("\n--- RUNNING APPLICATIONS ---")
        for app in list_running_apps():
            print(f"  {app['name']:<30} {app['bundle_id']}")
    
    elif "--dump" in sys.argv:
        dump_full_hierarchy(None)
    
    elif "--hittest" in sys.argv:
        print("\n--- HIT-TEST MODE ---")
        print("Move your mouse over djay Pro window elements...")
        print("Will sample 5 positions and report what's found.\n")
        
        import time
        
        # Get current mouse position and sample around it
        for i in range(5):
            event = Quartz.CGEventCreate(None)
            loc = Quartz.CGEventGetLocation(event)
            print(f"\nSampling mouse position: ({loc.x:.0f}, {loc.y:.0f})")
            
            element = get_element_at_position(loc.x, loc.y)
            if element:
                info = get_ax_info(element)
                print(f"  Found: [{info.get('AXRole')}] {info.get('AXTitle', '')} = {info.get('AXValue', '')}")
                
                # Walk up to parent
                parent = get_ax_attribute(element, "AXParent")
                if parent:
                    parent_info = get_ax_info(parent)
                    print(f"  Parent: [{parent_info.get('AXRole')}] {parent_info.get('AXTitle', '')}")
            else:
                print("  No element found")
            
            time.sleep(1)
    
    else:
        app = investigate_djay()
        
        if app:
            print("\n" + "=" * 60)
            print("INVESTIGATION COMPLETE")
            print("=" * 60)
            print("\nNext steps:")
            print("  - Run with --dump to export full hierarchy to JSON")
            print("  - Run with --hittest to probe elements under mouse")
            print("  - Use find_elements_by_role() to locate specific controls")
            print("  - Check sliders for crossfader/volume/EQ values")
            print("  - Look for track info in AXStaticText elements")
