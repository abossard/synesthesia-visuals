#!/usr/bin/env python3
"""
VirtualDJ status via screenshot + OCR.

Uses macOS Vision framework to read track info from VDJ window.
Much slower than djay_status.py (~1-2 sec) but VDJ doesn't expose accessibility API.
"""

import subprocess
import re
import sys

try:
    import Quartz
    from Foundation import NSURL
    import Vision
    import AppKit
except ImportError:
    print("ERROR: pyobjc required (pip install pyobjc-framework-Vision pyobjc-framework-Quartz)")
    sys.exit(1)

VDJ_BUNDLE_ID = 'com.atomixproductions.virtualdj'


def find_vdj_window_id():
    """Find VirtualDJ window ID and bounds."""
    window_list = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly,
        Quartz.kCGNullWindowID
    )
    
    for window in window_list:
        owner = window.get('kCGWindowOwnerName', '')
        if 'virtual' in owner.lower() and 'dj' in owner.lower():
            bounds = window.get('kCGWindowBounds', {})
            return window.get('kCGWindowNumber'), bounds
    return None, None


def capture_window_direct(window_id, bounds, crop_ratio=None):
    """Capture window directly via Quartz (faster than screencapture subprocess)."""
    # Capture the window
    cg_image = Quartz.CGWindowListCreateImage(
        Quartz.CGRectNull,  # Capture just this window
        Quartz.kCGWindowListOptionIncludingWindow,
        window_id,
        Quartz.kCGWindowImageBoundsIgnoreFraming
    )
    
    if not cg_image:
        return None
    
    # Optional: crop to region for faster OCR (but changes coordinate system)
    if crop_ratio and crop_ratio < 1.0:
        width = Quartz.CGImageGetWidth(cg_image)
        height = Quartz.CGImageGetHeight(cg_image)
        # Crop from top (y=0 in CG is bottom, so crop from height - crop_height)
        crop_height = int(height * crop_ratio)
        crop_width = int(width * crop_ratio)
        crop_rect = Quartz.CGRectMake(0, height - crop_height, crop_width, crop_height)
        cropped = Quartz.CGImageCreateWithImageInRect(cg_image, crop_rect)
        return cropped if cropped else cg_image
    
    return cg_image


def capture_window(window_id, output_path="/tmp/vdj_screenshot.png"):
    """Capture window screenshot (fallback method)."""
    result = subprocess.run(
        ["screencapture", "-l", str(window_id), "-x", output_path],
        capture_output=True, text=True
    )
    return result.returncode == 0


def ocr_cgimage(cg_image):
    """Run OCR directly on CGImage (no file I/O)."""
    if not cg_image:
        return []
    
    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg_image, None)
    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelFast)
    
    success, error = handler.performRequests_error_([request], None)
    if not success:
        return []
    
    results = []
    for obs in request.results():
        text = obs.topCandidates_(1)[0].string()
        bbox = obs.boundingBox()
        y = 1 - bbox.origin.y - bbox.size.height
        x = bbox.origin.x
        results.append((y, x, text))
    
    results.sort()
    return results


def ocr_image(image_path):
    """Run OCR on image and return list of (y, x, text) tuples."""
    image_url = NSURL.fileURLWithPath_(image_path)
    image_source = Quartz.CGImageSourceCreateWithURL(image_url, None)
    if not image_source:
        return []
    
    cg_image = Quartz.CGImageSourceCreateImageAtIndex(image_source, 0, None)
    if not cg_image:
        return []
    
    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg_image, None)
    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelFast)  # Fast mode for speed
    
    success, error = handler.performRequests_error_([request], None)
    if not success:
        return []
    
    results = []
    for obs in request.results():
        text = obs.topCandidates_(1)[0].string()
        bbox = obs.boundingBox()
        y = 1 - bbox.origin.y - bbox.size.height  # Flip Y (0=top)
        x = bbox.origin.x
        results.append((y, x, text))
    
    results.sort()
    return results


def parse_time_to_seconds(time_str):
    """Convert time string like '3:56.2' or '0:36.2' to seconds."""
    if not time_str:
        return None
    # Handle formats: 3:56.2, 03:56, 3:56
    match = re.match(r'(\d+):(\d+)(?:\.(\d+))?', time_str)
    if match:
        mins = int(match.group(1))
        secs = int(match.group(2))
        return mins * 60 + secs
    return None


def extract_deck_info(ocr_results, deck=None):
    """
    Extract deck info from OCR results.
    
    VDJ layout (approximate positions):
    - Deck 1: x < 0.45 (left side)
    - Deck 2: x > 0.55 (right side)
    
    If deck is None, returns the one that appears to be playing (has track info).
    """
    deck1 = _extract_single_deck(ocr_results, deck_num=1)
    deck2 = _extract_single_deck(ocr_results, deck_num=2)
    
    if deck == 1:
        return deck1
    elif deck == 2:
        return deck2
    
    # Return both decks
    return {'deck1': deck1, 'deck2': deck2}


def _extract_single_deck(ocr_results, deck_num):
    """Extract info for a single deck."""
    result = {
        'deck': deck_num,
        'track': None,
        'artist': None,
        'bpm': None,
        'key': None,
        'elapsed_sec': None,
        'remaining_sec': None,
        'duration_sec': None,
    }
    
    # Define X boundaries for each deck
    if deck_num == 1:
        x_min, x_max = 0.0, 0.45
        track_x_min, track_x_max = 0.0, 0.15
        info_x_min, info_x_max = 0.28, 0.45  # Wider range for time/BPM/key
    else:  # deck 2
        x_min, x_max = 0.55, 1.0
        track_x_min, track_x_max = 0.65, 0.95
        info_x_min, info_x_max = 0.59, 0.72  # Wider range
    
    # Collect title/artist candidates first (same Y region, pick by position)
    title_candidates = []  # (y, x, text)
    artist_candidates = []
    
    for y, x, text in ocr_results:
        if not (x_min <= x <= x_max):
            continue
        
        # Title region (y ≈ 0.19-0.21)
        if 0.18 <= y <= 0.215 and track_x_min <= x <= track_x_max and len(text) > 5:
            title_candidates.append((y, x, text))
        
        # Artist region (y ≈ 0.21-0.25, slightly below title)
        if 0.21 <= y <= 0.26 and track_x_min <= x <= track_x_max and len(text) > 5:
            artist_candidates.append((y, x, text))
        
        # BPM (format: 126.00)
        if re.match(r'^\d{2,3}\.\d{2}$', text):
            if 0.18 <= y <= 0.35 and info_x_min <= x <= info_x_max:
                result['bpm'] = text
        
        # Key (format: 10B, 02B, etc.)
        key_match = re.search(r'(\d{1,2}[ABab])', text.strip())
        if key_match:
            if 0.20 <= y <= 0.26 and info_x_min <= x <= info_x_max:
                result['key'] = key_match.group(1).upper()
        
        # Duration from "TOTAL" line
        total_match = re.search(r'(\d+:\d+\.\d+)\s*TOTAL|TOTAL\s*(\d+:\d+\.\d+)', text)
        if total_match:
            time_str = total_match.group(1) or total_match.group(2)
            result['duration_sec'] = parse_time_to_seconds(time_str)
        
        # Time values (elapsed/remaining) - handle OCR errors like 'o' for '0'
        # Clean common OCR errors first
        clean_text = text.replace('o', '0').replace('O', '0')
        time_match = re.match(r'^(\d+:\d+\.\d+)$', clean_text)
        if time_match and 0.35 <= y <= 0.42 and info_x_min <= x <= info_x_max:
            time_val = parse_time_to_seconds(time_match.group(1))
            if time_val is not None:
                # VDJ layout: lower Y = elapsed (top), higher Y = remaining (bottom)
                # y ≈ 0.36-0.37 = elapsed, y ≈ 0.38-0.39 = remaining
                if y < 0.375:
                    # This is elapsed time (upper position)
                    result['elapsed_sec'] = time_val
                else:
                    # This is remaining time (lower position)
                    result['remaining_sec'] = time_val
    
    # Pick track: longest text in title region (excluding short artist names)
    if title_candidates:
        # Sort by length descending, pick longest
        title_candidates.sort(key=lambda t: len(t[2]), reverse=True)
        result['track'] = title_candidates[0][2]
    
    # Pick artist: from artist region, different from track
    if artist_candidates and result['track']:
        for y, x, text in sorted(artist_candidates, key=lambda t: len(t[2]), reverse=True):
            if text != result['track'] and len(text) > 10:
                result['artist'] = text
                break
    
    # Fallback: calculate duration from elapsed + remaining
    if result['duration_sec'] is None and result['elapsed_sec'] and result['remaining_sec']:
        result['duration_sec'] = result['elapsed_sec'] + result['remaining_sec']
    
    return result


def get_current_playing():
    """Get current VirtualDJ playback info via screenshot + OCR.
    
    Returns dict with 'deck1', 'deck2', and 'active_deck' keys.
    'active_deck' is a heuristic guess based on elapsed time (higher = playing).
    """
    # Check if VDJ is running
    ws = AppKit.NSWorkspace.sharedWorkspace()
    vdj_running = False
    for app in ws.runningApplications():
        if app.bundleIdentifier() == VDJ_BUNDLE_ID:
            vdj_running = True
            break
    
    if not vdj_running:
        return None, "VirtualDJ not running"
    
    # Find window and capture directly (fast path)
    window_id, bounds = find_vdj_window_id()
    if not window_id:
        return None, "VirtualDJ window not found"
    
    # Try direct capture (faster - no subprocess, no file I/O)
    cg_image = capture_window_direct(window_id, bounds, crop_ratio=None)
    if cg_image:
        ocr_results = ocr_cgimage(cg_image)
    else:
        # Fallback to subprocess capture
        screenshot_path = "/tmp/vdj_screenshot.png"
        if not capture_window(window_id, screenshot_path):
            return None, "Failed to capture screenshot"
        ocr_results = ocr_image(screenshot_path)
    
    if not ocr_results:
        return None, "OCR failed or no text found"
    
    # Parse both decks
    result = extract_deck_info(ocr_results)
    
    # Check if at least one deck has track info
    if not result['deck1']['track'] and not result['deck2']['track']:
        return None, "Could not identify playing track on either deck"
    
    # Determine active deck heuristic:
    # - Deck NOT at the end of track is likely playing
    # - If both mid-song, the one with less remaining time is playing out
    # - If only one deck has a track, that's the active one
    deck1 = result['deck1']
    deck2 = result['deck2']
    
    if deck1['track'] and not deck2['track']:
        result['active_deck'] = 1
    elif deck2['track'] and not deck1['track']:
        result['active_deck'] = 2
    else:
        # Both have tracks - check which is actively playing (not at end)
        remaining1 = deck1.get('remaining_sec')
        remaining2 = deck2.get('remaining_sec')
        elapsed1 = deck1.get('elapsed_sec') or 0
        elapsed2 = deck2.get('elapsed_sec') or 0
        
        # Deck at 0:00 remaining is stopped/finished
        deck1_at_end = remaining1 is not None and remaining1 <= 1
        deck2_at_end = remaining2 is not None and remaining2 <= 1
        
        if deck1_at_end and not deck2_at_end:
            result['active_deck'] = 2
        elif deck2_at_end and not deck1_at_end:
            result['active_deck'] = 1
        elif remaining1 is not None and remaining2 is not None:
            # Both mid-song: less remaining = further along = likely playing
            result['active_deck'] = 1 if remaining1 < remaining2 else 2
        elif elapsed1 > elapsed2:
            result['active_deck'] = 1
        elif elapsed2 > elapsed1:
            result['active_deck'] = 2
        else:
            result['active_deck'] = 1  # Default
    
    return result, None


def _print_deck(deck_info, deck_label, is_active=False):
    """Print info for a single deck."""
    if not deck_info or not deck_info.get('track'):
        print(f'  {deck_label}: (empty)')
        return
    
    active_marker = ' ▶ PLAYING' if is_active else ''
    print(f'\n  [{deck_label}]{active_marker}')
    print(f'    Track:     {deck_info["track"]}')
    if deck_info.get('artist'):
        print(f'    Artist:    {deck_info["artist"]}')
    if deck_info.get('elapsed_sec') is not None:
        mins, secs = divmod(deck_info['elapsed_sec'], 60)
        print(f'    Position:  {int(mins)}:{int(secs):02d} ({deck_info["elapsed_sec"]} sec)')
    if deck_info.get('duration_sec'):
        mins, secs = divmod(deck_info['duration_sec'], 60)
        print(f'    Duration:  {int(mins)}:{int(secs):02d} ({deck_info["duration_sec"]} sec)')
    if deck_info.get('remaining_sec'):
        mins, secs = divmod(deck_info['remaining_sec'], 60)
        print(f'    Remaining: {int(mins)}:{int(secs):02d} ({deck_info["remaining_sec"]} sec)')
    if deck_info.get('bpm'):
        print(f'    BPM:       {deck_info["bpm"]}')
    if deck_info.get('key'):
        print(f'    Key:       {deck_info["key"]}')


def main():
    # Debug: print OCR results to tune parsing
    debug = '--debug' in sys.argv
    result, error = get_current_playing()
    
    if debug:
        # Re-run OCR for debug output
        window_id, _ = find_vdj_window_id()
        if window_id:
            ocr_results = ocr_image("/tmp/vdj_screenshot.png")
            print("\n=== OCR DEBUG (DECK 1: x<0.45) ===")
            for y, x, text in sorted(ocr_results):
                if x < 0.45 and y < 0.45:
                    print(f"  [{y:.2f},{x:.2f}] {text}")
            print("\n=== OCR DEBUG (DECK 2: x>0.50) ===")
            for y, x, text in sorted(ocr_results):
                if x > 0.50 and y < 0.45:
                    print(f"  [{y:.2f},{x:.2f}] {text}")
            print("=================\n")
    
    if error:
        print(f'Error: {error}')
        return
    
    if not result:
        print('No track info found')
        return
    
    print('=' * 50)
    print('NOW PLAYING (VirtualDJ)')
    print('=' * 50)
    
    active = result.get('active_deck', 0)
    
    _print_deck(result.get('deck1'), 'DECK 1', is_active=(active == 1))
    _print_deck(result.get('deck2'), 'DECK 2', is_active=(active == 2))


if __name__ == '__main__':
    main()
