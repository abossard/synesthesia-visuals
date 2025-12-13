#!/usr/bin/env python3
"""Quick script to get current djay Pro status - FAST version using iterative search."""

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
    err, value = ApplicationServices.AXUIElementCopyAttributeValue(element, attribute, None)
    return value if err == 0 else None

def collect_all_elements(root, max_depth=4):
    """Collect all elements iteratively (faster than recursive)."""
    elements = []
    stack = [(root, 0)]
    
    while stack:
        element, depth = stack.pop()
        if depth > max_depth:
            continue
        
        title = get_ax_attribute(element, 'AXTitle') or ''
        desc = get_ax_attribute(element, 'AXDescription') or ''
        value = get_ax_attribute(element, 'AXValue')
        
        elements.append({
            'title': title,
            'desc': desc, 
            'value': value,
            'combined': (title + ' ' + desc).lower()
        })
        
        children = get_ax_attribute(element, 'AXChildren')
        if children:
            for child in children:
                stack.append((child, depth + 1))
    
    return elements

def find_by_text(elements, text):
    """Find elements containing text in title/desc."""
    text_lower = text.lower()
    return [e for e in elements if text_lower in e['combined']]

def parse_time_to_seconds(time_str):
    """Convert time string like '01:56' or '-04:07' to seconds."""
    if not time_str:
        return None
    # Remove leading minus for remaining time
    time_str = time_str.lstrip('-')
    match = re.match(r'(\d+):(\d+)', time_str)
    if match:
        minutes, seconds = int(match.group(1)), int(match.group(2))
        return minutes * 60 + seconds
    return None

def get_current_playing():
    """Get info about the currently playing song."""
    # Find djay Pro
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
    elements = collect_all_elements(window, max_depth=5)
    
    # Find playing deck and crossfader position
    deck1_playing = False
    deck2_playing = False
    crossfader = 50  # default middle
    
    for p in find_by_text(elements, 'play / pause, deck 1')[:1]:
        deck1_playing = p['value'] == 'Active'
    for p in find_by_text(elements, 'play / pause, deck 2')[:1]:
        deck2_playing = p['value'] == 'Active'
    
    for c in find_by_text(elements, 'crossfader')[:1]:
        if c['value']:
            try:
                crossfader = int(c['value'].replace('%', ''))
            except:
                pass
    
    # Determine active deck (playing + crossfader position)
    active_deck = None
    if deck1_playing and deck2_playing:
        # Both playing - use crossfader
        active_deck = 1 if crossfader < 50 else 2
    elif deck1_playing:
        active_deck = 1
    elif deck2_playing:
        active_deck = 2
    
    if not active_deck:
        return None, "No deck playing"
    
    # Get track info for active deck
    result = {
        'deck': active_deck,
        'track': None,
        'artist': None,
        'elapsed_str': None,
        'elapsed_sec': None,
        'remaining_str': None,
        'remaining_sec': None,
        'duration_sec': None,
        'key': None,
        'crossfader': crossfader,
    }
    
    # Title
    for t in find_by_text(elements, f'title, deck {active_deck}')[:1]:
        result['track'] = t['value']
    
    # Artist
    for a in find_by_text(elements, f'artist, deck {active_deck}')[:1]:
        result['artist'] = a['value']
    
    # Elapsed time (may show as remaining depending on UI setting)
    for e in find_by_text(elements, f'elapsed time, deck {active_deck}')[:1]:
        result['elapsed_str'] = e['value']
        result['elapsed_sec'] = parse_time_to_seconds(e['value'])
    
    # Remaining time
    for r in find_by_text(elements, f'remaining time, deck {active_deck}')[:1]:
        result['remaining_str'] = r['value']
        result['remaining_sec'] = parse_time_to_seconds(r['value'])
    
    # If only remaining is available, we can't calculate position without duration
    # If only elapsed is available, that IS the position
    # If both available, calculate duration
    if result['elapsed_sec'] is not None and result['remaining_sec'] is not None:
        result['duration_sec'] = result['elapsed_sec'] + result['remaining_sec']
    
    # Handle case where UI shows remaining time in the elapsed slot (starts with -)
    if result['elapsed_str'] and result['elapsed_str'].startswith('-'):
        # The "elapsed" field is actually showing remaining time
        result['remaining_str'] = result['elapsed_str']
        result['remaining_sec'] = parse_time_to_seconds(result['elapsed_str'])
        result['elapsed_str'] = None
        result['elapsed_sec'] = None
    
    # Key
    for k in find_by_text(elements, f'key, deck {active_deck}')[:1]:
        result['key'] = k['value']
    
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
        mins, secs = divmod(result['duration_sec'], 60)
        print(f'  Duration:  {mins}:{secs:02d} ({result["duration_sec"]} sec total)')
    if result['remaining_sec']:
        print(f'  Remaining: {result["remaining_str"]} ({result["remaining_sec"]} sec left)')
    if result['elapsed_sec'] is None and result['remaining_sec']:
        print(f'  (UI shows remaining time only - position unknown)')
    print(f'  Key:       {result["key"]}')
    print(f'  Crossfader: {result["crossfader"]}%')

if __name__ == '__main__':
    main()
