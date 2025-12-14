#!/usr/bin/env python3
"""
VirtualDJ status via screenshot + OCR.

Uses macOS Vision framework to read track info from VDJ window.
Slower than djay_status.py (~1-2 sec) but VDJ doesn't expose accessibility API.

Master Deck Detection:
    Primary: GAIN fader position analysis (pixel scanning for gray handles)
    Fallback: Elapsed time progression tracking

Fader Detection Details:
    - Left fader (Deck 1): x=0.474 of window width
    - Right fader (Deck 2): x=0.526 of window width  
    - Y range: 0.22-0.42 of window height
    - Handle color: gray ~RGB(114,114,114)
    - Lower Y = fader UP = louder = master

Usage:
    python vdj_status.py           # Show current status
    python vdj_status.py --debug   # Show OCR debug output
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


# =============================================================================
# MASTER DECK STATE TRACKING
# =============================================================================

class MasterDeckTracker:
    """
    Tracks which deck is the master (active) based on elapsed time changes.
    
    Rules:
    - First deck with elapsed time increasing = master
    - Stays master until OTHER deck starts having elapsed time increase
    - Then the other deck becomes the new master
    """
    
    def __init__(self):
        self._master_deck = None  # 1 or 2
        self._prev_elapsed = {1: None, 2: None}
    
    def update(self, deck1_elapsed: float, deck2_elapsed: float) -> int:
        """
        Update with current elapsed times and return the master deck.
        
        Returns: 1 or 2 (master deck number)
        """
        # Detect which deck's elapsed time is increasing
        deck1_increasing = (
            self._prev_elapsed[1] is not None 
            and deck1_elapsed is not None 
            and deck1_elapsed > self._prev_elapsed[1] + 0.3  # threshold for noise
        )
        deck2_increasing = (
            self._prev_elapsed[2] is not None 
            and deck2_elapsed is not None 
            and deck2_elapsed > self._prev_elapsed[2] + 0.3
        )
        
        # Update previous values
        if deck1_elapsed is not None:
            self._prev_elapsed[1] = deck1_elapsed
        if deck2_elapsed is not None:
            self._prev_elapsed[2] = deck2_elapsed
        
        # Determine master deck
        if self._master_deck is None:
            # Initial: first deck with increasing time becomes master
            if deck1_increasing:
                self._master_deck = 1
            elif deck2_increasing:
                self._master_deck = 2
            elif deck1_elapsed and deck1_elapsed > 0:
                self._master_deck = 1  # fallback: deck with elapsed time
            elif deck2_elapsed and deck2_elapsed > 0:
                self._master_deck = 2
            else:
                self._master_deck = 1  # default
        else:
            # Transition: if OTHER deck starts increasing, it becomes master
            if self._master_deck == 1 and deck2_increasing:
                self._master_deck = 2
            elif self._master_deck == 2 and deck1_increasing:
                self._master_deck = 1
        
        return self._master_deck
    
    def reset(self):
        """Reset state (e.g., on new session)."""
        self._master_deck = None
        self._prev_elapsed = {1: None, 2: None}


# Global tracker instance
_master_tracker = MasterDeckTracker()

# Smoothing for master deck detection
_last_master = 1
_last_fader_master = 0  # Track last fader-based detection
_MASTER_HOLD_THRESHOLD = 1  # Require N consecutive detections before switching (1 = immediate)


def detect_master_from_faders(cg_image) -> tuple:
    """
    Detect master deck by analyzing the GAIN fader positions.
    
    The VDJ mixer has two vertical GAIN faders in the center.
    The deck with fader higher up = louder = master.
    
    Fader Layout (VDJ default skin):
        - Left fader (Deck 1): x ≈ 0.474 of window width
        - Right fader (Deck 2): x ≈ 0.526 of window width
        - Fader travel range: y ≈ 0.22 (top/loud) to 0.42 (bottom/quiet)
        - Handle appearance: gray horizontal bar ~RGB(114,114,114)
    
    Detection Method:
        1. Scan vertical strip at each fader's X position
        2. Find row with most gray pixels (the handle)
        3. Compare Y positions: lower Y = higher on screen = louder
    
    Note: Audio level METERS (blue/cyan) show deck activity but NOT output level.
          The FADER position determines what actually goes to master output.
    
    Args:
        cg_image: CGImage from window capture
    
    Returns:
        tuple: (deck_num, left_fader_y, right_fader_y)
            - deck_num: 1 (left louder), 2 (right louder), or 0 (can't determine)
            - left_fader_y: normalized Y position (0-1) of left fader handle
            - right_fader_y: normalized Y position (0-1) of right fader handle
    """
    if not cg_image:
        return 0, 0, 0
    
    width = Quartz.CGImageGetWidth(cg_image)
    height = Quartz.CGImageGetHeight(cg_image)
    
    data_provider = Quartz.CGImageGetDataProvider(cg_image)
    data = Quartz.CGDataProviderCopyData(data_provider)
    bytes_per_row = Quartz.CGImageGetBytesPerRow(cg_image)
    bpp = Quartz.CGImageGetBitsPerPixel(cg_image) // 8
    
    def find_fader_handle_y(x_center_norm, y_start_norm=0.22, y_end_norm=0.42):
        """
        Find the Y position of the fader handle by scanning for gray pixels.
        
        Args:
            x_center_norm: Normalized X position (0-1) of fader center
            y_start_norm: Top of search region (0.22 = fader max/loud)
            y_end_norm: Bottom of search region (0.42 = fader min/quiet)
        
        Returns:
            Normalized Y position (0-1) of handle, or None if not found.
            Lower Y = higher on screen = fader UP = louder.
        """
        best_y = None
        best_score = 0
        
        # Narrow search band around the fader track
        x_start = int((x_center_norm - 0.012) * width)
        x_end = int((x_center_norm + 0.012) * width)
        
        for y in range(int(y_start_norm * height), int(y_end_norm * height)):
            row_score = 0
            for x in range(x_start, x_end):
                offset = y * bytes_per_row + x * bpp
                if offset + 3 < len(data):
                    b, g, r = data[offset], data[offset+1], data[offset+2]
                    # Fader handle is gray (~114,114,114)
                    # Look for pixels where R≈G≈B and in range 90-140
                    if 90 < r < 140 and 90 < g < 140 and 90 < b < 140:
                        if abs(r - g) < 15 and abs(g - b) < 15:
                            row_score += 1
            
            if row_score > best_score:
                best_score = row_score
                best_y = y
        
        return (best_y / height) if best_y and best_score > 5 else None
    
    # Corrected fader positions based on user measurement:
    # Left fader (Deck 1) at x=0.474
    # Right fader (Deck 2) at x=0.526
    left_y = find_fader_handle_y(0.474)
    right_y = find_fader_handle_y(0.526)
    
    if left_y is None or right_y is None:
        return 0, left_y or 0, right_y or 0
    
    # Lower Y = higher on screen = fader UP = louder
    # Require significant difference (1% of screen height)
    threshold = 0.01
    
    if left_y < right_y - threshold:
        return 1, left_y, right_y  # Left fader higher = Deck 1 louder
    elif right_y < left_y - threshold:
        return 2, left_y, right_y  # Right fader higher = Deck 2 louder
    else:
        return 0, left_y, right_y  # Faders approximately equal


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
    
    # Determine active (master) deck - try fader detection first, then fallback to elapsed time tracking
    global _last_master, _last_fader_master
    
    deck1 = result['deck1']
    deck2 = result['deck2']
    
    # Primary: Detect master from GAIN fader positions
    # Capture fresh full window for fader detection (OCR may have invalidated previous image)
    fader_image = capture_window_direct(window_id, bounds, crop_ratio=None)
    fader_master, left_y, right_y = detect_master_from_faders(fader_image) if fader_image else (0, 0, 0)
    
    if fader_master > 0:
        # Fader detection succeeded - update immediately
        _last_fader_master = fader_master
        _last_master = fader_master
        result['active_deck'] = fader_master
        result['_master_source'] = 'faders'
        result['_fader_positions'] = (left_y, right_y)
    elif _last_fader_master > 0:
        # Use last known fader-based master (fader detection temporarily failed)
        result['active_deck'] = _last_fader_master
        result['_master_source'] = 'faders_cached'
    else:
        # Fallback: Use elapsed time progression tracking
        elapsed1 = deck1.get('elapsed_sec')
        elapsed2 = deck2.get('elapsed_sec')
        result['active_deck'] = _master_tracker.update(elapsed1, elapsed2)
        result['_master_source'] = 'elapsed_tracking'
    
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
