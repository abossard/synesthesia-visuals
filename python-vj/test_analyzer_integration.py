#!/usr/bin/env python3
"""
Integration test for Python audio analyzer and OSC visualizer.

This script:
1. Creates a test audio analyzer with mock audio input
2. Verifies OSC messages are being sent correctly
3. Checks message format and data types
"""

import time
import logging
import numpy as np
from pythonosc import dispatcher, osc_server
from audio_analyzer import AudioConfig, AudioAnalyzer, DeviceManager

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Track received messages
received_messages = {}
message_counts = {}


def test_analyzer_osc_output():
    """Test that analyzer sends correct OSC messages."""
    logger.info("Testing audio analyzer OSC output...")
    
    # Create OSC receiver to monitor messages
    disp = dispatcher.Dispatcher()
    
    def capture_message(addr, *args):
        """Capture OSC messages for verification."""
        received_messages[addr] = args
        message_counts[addr] = message_counts.get(addr, 0) + 1
        logger.debug(f"Received {addr}: {len(args)} values")
    
    # Map all expected addresses
    for addr in ['/audio/levels', '/audio/spectrum', '/audio/beats', 
                 '/audio/bpm', '/audio/pitch', '/audio/spectral', '/audio/structure']:
        disp.map(addr, capture_message)
    
    # Start OSC server
    server = osc_server.ThreadingOSCUDPServer(("127.0.0.1", 9001), disp)
    logger.info("OSC receiver started on port 9001")
    
    import threading
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    
    # Create audio analyzer configuration
    config = AudioConfig(
        sample_rate=44100,
        block_size=512,
        osc_host="127.0.0.1",
        osc_port=9001,  # Send to our test receiver
        enable_essentia=False,  # Disable Essentia for testing
        enable_logging=False,  # Reduce noise
    )
    
    device_manager = DeviceManager()
    
    # Create mock OSC callback
    def mock_osc_callback(address, values):
        """Mock callback that forwards to OSC client."""
        from pythonosc import udp_client
        client = udp_client.SimpleUDPClient("127.0.0.1", 9001)
        client.send_message(address, values)
    
    # Create analyzer with mock callback
    analyzer = AudioAnalyzer(config, device_manager, mock_osc_callback)
    
    # Generate mock audio data and process
    logger.info("Generating mock audio data...")
    for i in range(10):
        # Create mock audio block (sine wave)
        t = np.linspace(0, config.block_size / config.sample_rate, config.block_size)
        freq = 440.0  # A4
        audio_block = 0.5 * np.sin(2 * np.pi * freq * t)
        audio_block = audio_block.reshape(-1, 1)  # Mono
        
        # Process frame directly
        analyzer._process_frame(audio_block)
        
        time.sleep(0.01)  # Small delay
    
    # Wait for messages to arrive
    time.sleep(0.5)
    
    # Verify received messages
    logger.info("\n=== Verification Results ===")
    
    expected_addresses = [
        '/audio/levels',
        '/audio/spectrum',
        '/audio/beats',
        '/audio/bpm',
        '/audio/spectral',
    ]
    
    all_ok = True
    
    for addr in expected_addresses:
        if addr in received_messages:
            count = message_counts.get(addr, 0)
            values = received_messages[addr]
            logger.info(f"✓ {addr}: received {count} times, {len(values)} values")
            
            # Verify specific formats
            if addr == '/audio/levels' and len(values) != 8:
                logger.error(f"  ✗ Expected 8 values, got {len(values)}")
                all_ok = False
            elif addr == '/audio/spectrum' and len(values) != 32:
                logger.error(f"  ✗ Expected 32 values, got {len(values)}")
                all_ok = False
            elif addr == '/audio/beats' and len(values) != 5:
                logger.error(f"  ✗ Expected 5 values, got {len(values)}")
                all_ok = False
            elif addr == '/audio/bpm' and len(values) != 2:
                logger.error(f"  ✗ Expected 2 values, got {len(values)}")
                all_ok = False
            elif addr == '/audio/spectral' and len(values) != 3:
                logger.error(f"  ✗ Expected 3 values, got {len(values)}")
                all_ok = False
        else:
            logger.error(f"✗ {addr}: NOT RECEIVED")
            all_ok = False
    
    # Stop server
    server.shutdown()
    
    if all_ok:
        logger.info("\n✓ All OSC message tests PASSED")
        return True
    else:
        logger.error("\n✗ Some OSC message tests FAILED")
        return False


if __name__ == "__main__":
    success = test_analyzer_osc_output()
    exit(0 if success else 1)
