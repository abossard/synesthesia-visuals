#!/usr/bin/env python3
"""Quick script to get current djay Pro status - OPTIMIZED for speed."""

import sys
import re
try:
    import ApplicationServices
    import AppKit
except ImportError:
    print("ERROR: pyobjc required")
    sys.exit(1)

DJAY_BUNDLE_ID = 'com.algoriddim.djay-iphone-free'

def get_ax_attribute(element, attribute):
    """Get accessibility attribute with minimal overhead."""
    err, value = ApplicationServices.AXUIElementCopyAttributeValue(element, attribute, None)
    return value if err == 0 else None

def parse_time_to_seconds(time_str):
    """Convert time string like '01:56' or '-04:07' to seconds."""
    if not time_str:
        return None
    time_str = time_str.lstrip('-')
    match = re.match(r'(\d+):(\d+)', time_str)
    if match:
        return int(match.group(1)) * 60 + int(match.group(2))
    return None

def find_elements_fast(root, targets, max_depth=4):
    """
    Fast targeted search - only collects elements matching target patterns.
    Returns dict of {target: first matching element's value}
    """
    results = {t: None for t in targets}
    targets_lower = {t: t.lower() for t in targets}
    found_count = 0
    total_targets = len(targets)
    
    stack = [(root, 0)]
    while stack and found_count < total_targets:
        element, depth = stack.pop()
        if depth > max_depth:
            continue
        
        desc = get_ax_attribute(element, 'AXDescription') or ''
        desc_lower = desc.lower()
        
        # Check if this element matches any target
        for target, target_lower in targets_lower.items():
            if results[target] is None and target_lower in desc_lower:
                results[target] = get_ax_attribute(element, 'AXValue')
                found_count += 1
        
        children = get_ax_attribute(element, 'AXChildren')
        if children:
            for child in children:
                stack.append((child, depth + 1))
    
    return results

def find_automix_row_fast(window, track_title, max_rows=30):
    """Fast Automix search - only check visible/recent rows."""
    if not track_title:
        return None
    
    track_lower = track_title.lower()
    stack = [(window, 0)]
    
    while stack:
        el, d = stack.pop()
        if d > 3:
            continue
        
        role = get_ax_attribute(el, 'AXRole') or ''
        title = get_ax_attribute(el, 'AXTitle') or ''
        
        if role == 'AXTable' and 'Automix' in title:
            rows = get_ax_attribute(el, 'AXRows')
            if rows:
                for row in rows[:max_rows]:
                    cells = get_ax_attribute(row, 'AXChildren')
                    if not cells:
                        continue
                    
                    values = []
                    for cell in cells[:5]:
                        cell_children = get_ax_attribute(cell, 'AXChildren')
                        if cell_children:
                            for cc in cell_children[:1]:
                                val = get_ax_attribute(cc, 'AXValue')
                                if val:
                                    values.append(str(val))
                                    break
                    
                    if len(values) >= 3:
                        row_title = values[0].lower()
                        if track_lower in row_title or row_title in track_lower:
                            return {
                                'duration_str': values[2] if len(values) > 2 else None,
                                'duration_sec': parse_time_to_seconds(values[2]) if len(values) > 2 else None,
                                'bpm': values[4] if len(values) > 4 else None
                            }
            return None
        
        children = get_ax_attribute(el, 'AXChildren')
        if children:
            for c in children:
                stack.append((c, d + 1))
    
    return None

def get_current_playing():
    """Get info about the currently playing song - optimized."""
    workspace = AppKit.NSWorkspace.sharedWorkspace()
    pid = None
    for app in workspace.runningApplications():
        if app.bundleIdentifier() == DJAY_BUNDLE_ID:
            pid = app.processIdentifier()
            break
    
    if not pid:
        return None, "djay Pro not running"
    
    ax_app = ApplicationServices.AXUIElementCreateApplication(pid)
    windows = get_ax_attribute(ax_app, 'AXWindows')
    if not windows:
        return None, "No windows found"
    
    window = windows[0]
    
    # Single pass to get all needed elements
    targets = [
        'Play / Pause, Deck 1', 'Play / Pause, Deck 2', 'Crossfader',
        'Title, Deck 1', 'Title, Deck 2',
        'Artist, Deck 1', 'Artist, Deck 2',
        'Elapsed time, Deck 1', 'Elapsed time, Deck 2',
        'Remaining time, Deck 1', 'Remaining time, Deck 2',
        'Key, Deck 1', 'Key, Deck 2',
    ]
    
    data = find_elements_fast(window, targets, max_depth=4)
    
    deck1_playing = data.get('Play / Pause, Deck 1') == 'Active'
    deck2_playing = data.get('Play / Pause, Deck 2') == 'Active'
    
    crossfader = 50
    cf_val = data.get('Crossfader')
    if cf_val:
        try:
            crossfader = int(cf_val.replace('%', ''))
        except (ValueError, AttributeError):
            pass
    
    if deck1_playing and deck2_playing:
        active_deck = 1 if crossfader < 50 else 2
    elif deck1_playing:
        active_deck = 1
    elif deck2_playing:
        active_deck = 2
    else:
        return None, "No deck playing"
    
    elapsed_str = data.get(f'Elapsed time, Deck {active_deck}')
    remaining_str = data.get(f'Remaining time, Deck {active_deck}')
    
    if elapsed_str and elapsed_str.startswith('-'):
        remaining_str = elapsed_str
        elapsed_str = None
    
    elapsed_sec = parse_time_to_seconds(elapsed_str)
    remaining_sec = parse_time_to_seconds(remaining_str)
    
    duration_sec = None
    duration_str = None
    if elapsed_sec is not None and remaining_sec is not None:
        duration_sec = elapsed_sec + remaining_sec
    
    result = {
        'deck': active_deck,
        'track': data.get(f'Title, Deck {active_deck}'),
        'artist': data.get(f'Artist, Deck {active_deck}'),
        'elapsed_str': elapsed_str,
        'elapsed_sec': elapsed_sec,
        'remaining_str': remaining_str,
        'remaining_sec': remaining_sec,
        'duration_sec': duration_sec,
        'duration_str': duration_str,
        'bpm': None,
        'key': data.get(f'Key, Deck {active_deck}'),
        'crossfader': crossfader,
    }
    
    # Only search Automix if we need duration or BPM
    if result['track'] and (not result['duration_sec'] or not result['bpm']):
        automix_info = find_automix_row_fast(window, result['track'])
        if automix_info:
            if not result['duration_sec'] and automix_info.get('duration_sec'):
                result['duration_sec'] = automix_info['duration_sec']
                result['duration_str'] = automix_info['duration_str']
            if automix_info.get('bpm'):
                result['bpm'] = automix_info['bpm']
    
    if result['duration_sec'] and result['remaining_sec'] and result['elapsed_sec'] is None:
        result['elapsed_sec'] = result['duration_sec'] - result['remaining_sec']
        mins, secs = divmod(result['elapsed_sec'], 60)
        result['elapsed_str'] = f'{mins:02d}:{secs:02d}'
    
    return result, None

def main():
    result, error = get_current_playing()
    
    if error:
        print(f'Error: {error}')
        return
    
    if not result:
        print('No song currently playing')
        return
    
    print('=' * 50)
    print('NOW PLAYING')
    print('=' * 50)
    print(f'  Deck:      {result["deck"]}')
    print(f'  Track:     {result["track"]}')
    print(f'  Artist:    {result["artist"]}')
    if result['elapsed_sec'] is not None:
        print(f'  Position:  {result["elapsed_str"]} ({result["elapsed_sec"]} sec)')
    if result['duration_sec']:
        if result['duration_str']:
            print(f'  Duration:  {result["duration_str"]} ({result["duration_sec"]} sec total)')
        else:
            mins, secs = divmod(result['duration_sec'], 60)
            print(f'  Duration:  {mins}:{secs:02d} ({result["duration_sec"]} sec total)')
    if result['remaining_sec']:
        print(f'  Remaining: {result["remaining_str"]} ({result["remaining_sec"]} sec left)')
    if result['bpm']:
        print(f'  BPM:       {result["bpm"]}')
    print(f'  Key:       {result["key"]}')
    print(f'  Crossfader: {result["crossfader"]}%')

if __name__ == '__main__':
    main()
