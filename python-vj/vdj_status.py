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
    """Find VirtualDJ window ID."""
    window_list = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly,
        Quartz.kCGNullWindowID
    )
    
    for window in window_list:
        owner = window.get('kCGWindowOwnerName', '')
        if 'virtual' in owner.lower() and 'dj' in owner.lower():
            return window.get('kCGWindowNumber')
    return None


def capture_window(window_id, output_path="/tmp/vdj_screenshot.png"):
    """Capture window screenshot."""
    result = subprocess.run(
        ["screencapture", "-l", str(window_id), "-x", output_path],
        capture_output=True, text=True
    )
    return result.returncode == 0


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


def extract_deck_info(ocr_results):
    """
    Extract deck info from OCR results.
    
    VDJ layout (approximate Y positions, 0=top, 1=bottom):
    - 0.20: Track title
    - 0.22: Artist
    - 0.20: BPM (x≈0.37)
    - 0.22: Key (x≈0.38)  
    - 0.24-0.38: Time displays (TOTAL label at 0.25, times around 0.31-0.38)
    """
    result = {
        'deck': 1,
        'track': None,
        'artist': None,
        'bpm': None,
        'key': None,
        'elapsed_sec': None,
        'remaining_sec': None,
        'duration_sec': None,
    }
    
    # Collect candidates from left deck area (x < 0.45)
    for y, x, text in ocr_results:
        if x > 0.45:
            continue  # Skip right side
        
        # Track title (y ≈ 0.19-0.21, x < 0.40, long text)
        if 0.18 <= y <= 0.22 and x < 0.10 and len(text) > 15:
            if not result['track'] or len(text) > len(result['track']):
                result['track'] = text
        
        # Artist (y ≈ 0.21-0.24, below title)
        if 0.21 <= y <= 0.25 and x < 0.10 and len(text) > 10:
            if result['track'] and text != result['track']:
                result['artist'] = text
        
        # BPM (format: 126.00, typically at y≈0.20 or 0.31, x≈0.30-0.38)
        if re.match(r'^\d{2,3}\.\d{2}$', text):
            if 0.18 <= y <= 0.35 and 0.28 <= x <= 0.42:
                result['bpm'] = text
        
        # Key (format: 10B, 02B, etc. - may appear as "4 KEY ￿ 12A-" or just "10B v")
        key_match = re.search(r'(\d{1,2}[ABab])', text.strip())
        if key_match:
            if 0.20 <= y <= 0.26 and 0.30 <= x <= 0.42:
                result['key'] = key_match.group(1).upper()
        
        # Time values (format: 3:56.2 or 0:36.2)
        time_match = re.match(r'^(\d+:\d+\.\d+)$', text)
        if time_match and 0.23 <= y <= 0.42 and 0.28 <= x <= 0.42:
            time_val = parse_time_to_seconds(time_match.group(1))
            if time_val is not None:
                # Determine which time this is based on Y position
                if 0.23 <= y <= 0.28:
                    # Near "TOTAL" label - this is duration
                    result['duration_sec'] = time_val
                elif 0.35 <= y <= 0.40:
                    # Lower times - elapsed and remaining
                    if result['elapsed_sec'] is None:
                        result['elapsed_sec'] = time_val
                    elif result['remaining_sec'] is None:
                        # Smaller one is remaining
                        if time_val < result['elapsed_sec']:
                            result['remaining_sec'] = time_val
                        else:
                            result['remaining_sec'] = result['elapsed_sec']
                            result['elapsed_sec'] = time_val
    
    # Fallback: calculate duration from elapsed + remaining
    if result['duration_sec'] is None and result['elapsed_sec'] and result['remaining_sec']:
        result['duration_sec'] = result['elapsed_sec'] + result['remaining_sec']
    
    return result


def get_current_playing():
    """Get current VirtualDJ playback info via screenshot + OCR."""
    # Check if VDJ is running
    ws = AppKit.NSWorkspace.sharedWorkspace()
    vdj_running = False
    for app in ws.runningApplications():
        if app.bundleIdentifier() == VDJ_BUNDLE_ID:
            vdj_running = True
            break
    
    if not vdj_running:
        return None, "VirtualDJ not running"
    
    # Find window and capture
    window_id = find_vdj_window_id()
    if not window_id:
        return None, "VirtualDJ window not found"
    
    screenshot_path = "/tmp/vdj_screenshot.png"
    if not capture_window(window_id, screenshot_path):
        return None, "Failed to capture screenshot"
    
    # Run OCR
    ocr_results = ocr_image(screenshot_path)
    if not ocr_results:
        return None, "OCR failed or no text found"
    
    # Parse results
    result = extract_deck_info(ocr_results)
    
    if not result['track']:
        return None, "Could not identify playing track"
    
    return result, None


def main():
    # Debug: print OCR results to tune parsing
    debug = '--debug' in sys.argv
    result, error = get_current_playing()
    
    if debug:
        # Re-run OCR for debug output
        window_id = find_vdj_window_id()
        if window_id:
            ocr_results = ocr_image("/tmp/vdj_screenshot.png")
            print("\n=== OCR DEBUG ===")
            for y, x, text in sorted(ocr_results):
                if x < 0.45 and y < 0.45:  # Deck 1 region only
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
    print(f'  Track:     {result["track"]}')
    if result['artist']:
        print(f'  Artist:    {result["artist"]}')
    if result['elapsed_sec'] is not None:
        mins, secs = divmod(result['elapsed_sec'], 60)
        print(f'  Position:  {mins}:{secs:02d} ({result["elapsed_sec"]} sec)')
    if result['duration_sec']:
        mins, secs = divmod(result['duration_sec'], 60)
        print(f'  Duration:  {mins}:{secs:02d} ({result["duration_sec"]} sec)')
    if result['remaining_sec']:
        mins, secs = divmod(result['remaining_sec'], 60)
        print(f'  Remaining: {mins}:{secs:02d} ({result["remaining_sec"]} sec)')
    if result['bpm']:
        print(f'  BPM:       {result["bpm"]}')
    if result['key']:
        print(f'  Key:       {result["key"]}')


if __name__ == '__main__':
    main()
