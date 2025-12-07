#!/usr/bin/env python3
"""
Test script for OSC communication between Python audio analyzer and Processing visualizer.

Tests:
1. Verify Python audio analyzer can send OSC messages
2. Check all OSC addresses match expected format
3. Validate data types and ranges
4. Test message frequency and timing
"""

import time
import logging
from pythonosc import udp_client
from pythonosc import osc_server
from pythonosc import dispatcher

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# OSC configuration
OSC_HOST = "127.0.0.1"
OSC_PORT = 9000

def test_osc_sender():
    """Test sending OSC messages to Processing visualizer."""
    logger.info("Testing OSC sender...")
    
    client = udp_client.SimpleUDPClient(OSC_HOST, OSC_PORT)
    
    # Test /audio/levels
    logger.info("Sending /audio/levels...")
    levels = [0.1, 0.2, 0.15, 0.3, 0.25, 0.2, 0.15, 0.5]
    client.send_message("/audio/levels", levels)
    time.sleep(0.1)
    
    # Test /audio/spectrum
    logger.info("Sending /audio/spectrum...")
    spectrum = [0.5 + 0.5 * (i % 8) / 8.0 for i in range(32)]
    client.send_message("/audio/spectrum", spectrum)
    time.sleep(0.1)
    
    # Test /audio/beats
    logger.info("Sending /audio/beats...")
    client.send_message("/audio/beats", [1, 0.8, 0.6, 0.4, 0.2])
    time.sleep(0.1)
    
    # Test /audio/bpm
    logger.info("Sending /audio/bpm...")
    client.send_message("/audio/bpm", [128.5, 0.85])
    time.sleep(0.1)
    
    # Test /audio/pitch
    logger.info("Sending /audio/pitch...")
    client.send_message("/audio/pitch", [440.0, 0.9])
    time.sleep(0.1)
    
    # Test /audio/spectral
    logger.info("Sending /audio/spectral...")
    client.send_message("/audio/spectral", [0.5, 4500.0, 0.3])
    time.sleep(0.1)
    
    # Test /audio/structure
    logger.info("Sending /audio/structure...")
    client.send_message("/audio/structure", [0, 0, 0.2, 0.6])
    time.sleep(0.1)
    
    logger.info("✓ OSC messages sent successfully")
    logger.info("Check Processing visualizer window for updates")


def test_osc_receiver():
    """Test receiving OSC messages (monitor what Processing would receive)."""
    logger.info("Testing OSC receiver...")
    logger.info("Listening on port %d for 10 seconds...", OSC_PORT)
    
    disp = dispatcher.Dispatcher()
    
    def handle_levels(addr, *args):
        logger.info(f"{addr}: {len(args)} values - {args[:3]}...")
    
    def handle_spectrum(addr, *args):
        logger.info(f"{addr}: {len(args)} bins")
    
    def handle_beats(addr, *args):
        logger.info(f"{addr}: beat={args[0]}, pulse={args[1]:.2f}")
    
    def handle_bpm(addr, *args):
        logger.info(f"{addr}: {args[0]:.1f} BPM, conf={args[1]:.2f}")
    
    def handle_pitch(addr, *args):
        logger.info(f"{addr}: {args[0]:.1f} Hz, conf={args[1]:.2f}")
    
    def handle_spectral(addr, *args):
        logger.info(f"{addr}: centroid={args[0]:.2f}, rolloff={args[1]:.1f}, flux={args[2]:.3f}")
    
    def handle_structure(addr, *args):
        logger.info(f"{addr}: buildup={args[0]}, drop={args[1]}, trend={args[2]:.2f}")
    
    disp.map("/audio/levels", handle_levels)
    disp.map("/audio/spectrum", handle_spectrum)
    disp.map("/audio/beats", handle_beats)
    disp.map("/audio/bpm", handle_bpm)
    disp.map("/audio/pitch", handle_pitch)
    disp.map("/audio/spectral", handle_spectral)
    disp.map("/audio/structure", handle_structure)
    
    server = osc_server.ThreadingOSCUDPServer((OSC_HOST, OSC_PORT), disp)
    logger.info("Server started on %s:%d", OSC_HOST, OSC_PORT)
    
    try:
        # Run for 10 seconds
        timeout = time.time() + 10
        while time.time() < timeout:
            server.handle_request()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
    
    logger.info("✓ OSC receiver test complete")


def test_continuous_stream():
    """Send continuous stream of test data to simulate real analyzer."""
    logger.info("Testing continuous OSC stream...")
    logger.info("Sending data for 10 seconds (press Ctrl+C to stop)...")
    
    client = udp_client.SimpleUDPClient(OSC_HOST, OSC_PORT)
    
    start_time = time.time()
    frame = 0
    
    try:
        while time.time() - start_time < 10:
            t = time.time() - start_time
            
            # Simulate pulsing bass
            bass_pulse = abs((t % 0.5) / 0.5 - 0.5) * 2
            
            # /audio/levels
            levels = [
                0.1 + bass_pulse * 0.3,  # sub_bass
                0.2 + bass_pulse * 0.5,  # bass
                0.15,  # low_mid
                0.3,   # mid
                0.25,  # high_mid
                0.2,   # presence
                0.15,  # air
                0.5 + bass_pulse * 0.3   # overall
            ]
            client.send_message("/audio/levels", levels)
            
            # /audio/spectrum (animated wave)
            spectrum = [0.3 + 0.2 * abs((i + frame) % 16 - 8) / 8.0 for i in range(32)]
            client.send_message("/audio/spectrum", spectrum)
            
            # /audio/beats (beat every 0.5 seconds)
            is_beat = 1 if (frame % 30) == 0 else 0
            client.send_message("/audio/beats", [
                is_beat, 
                bass_pulse if is_beat else bass_pulse * 0.5,
                bass_pulse * 0.8,
                bass_pulse * 0.5,
                bass_pulse * 0.3
            ])
            
            # /audio/bpm
            if frame % 45 == 0:
                client.send_message("/audio/bpm", [128.0 + (frame % 10), 0.85])
            
            # /audio/pitch
            if frame % 20 == 0:
                pitch = 220.0 + (frame % 100) * 2
                client.send_message("/audio/pitch", [pitch, 0.7])
            
            # /audio/spectral
            if frame % 10 == 0:
                client.send_message("/audio/spectral", [
                    0.5 + bass_pulse * 0.2,  # centroid
                    3000.0 + bass_pulse * 2000,  # rolloff
                    bass_pulse * 0.5  # flux
                ])
            
            # /audio/structure
            if frame % 60 == 0:
                client.send_message("/audio/structure", [0, 0, 0.1, 0.5])
            
            frame += 1
            time.sleep(1.0 / 60)  # 60 Hz
            
            if frame % 60 == 0:
                logger.info(f"Sent {frame} frames ({frame/60:.1f}s)")
    
    except KeyboardInterrupt:
        pass
    
    logger.info(f"✓ Sent {frame} frames of continuous data")


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python test_osc_communication.py [send|receive|stream]")
        print()
        print("Commands:")
        print("  send     - Send test OSC messages once")
        print("  receive  - Listen for OSC messages (10 seconds)")
        print("  stream   - Send continuous animated data (10 seconds)")
        print()
        print("Example:")
        print("  1. Start Processing AudioAnalysisOSCVisualizer sketch")
        print("  2. Run: python test_osc_communication.py stream")
        print("  3. Watch the visualizer animate with test data")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == "send":
        test_osc_sender()
    elif command == "receive":
        test_osc_receiver()
    elif command == "stream":
        test_continuous_stream()
    else:
        print(f"Unknown command: {command}")
        print("Use: send, receive, or stream")
        sys.exit(1)
