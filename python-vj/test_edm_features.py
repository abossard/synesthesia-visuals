#!/usr/bin/env python3
"""
Test script for new EDM-specific OSC features.

Verifies that all 14 new EDM descriptor OSC messages are being sent correctly.
"""

import time
import logging
import numpy as np
from pythonosc import dispatcher, osc_server
from audio_analyzer import AudioConfig, AudioAnalyzer, DeviceManager
import threading

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Track received messages
received_messages = {}
message_counts = {}


def test_edm_features():
    """Test that all EDM features are sent via OSC."""
    logger.info("Testing EDM feature OSC output...")
    
    # Create OSC receiver to monitor messages
    disp = dispatcher.Dispatcher()
    
    def capture_message(addr, *args):
        """Capture OSC messages for verification."""
        received_messages[addr] = args
        message_counts[addr] = message_counts.get(addr, 0) + 1
        logger.debug(f"Received {addr}: {args}")
    
    # Map all EDM feature addresses
    edm_features = [
        '/beat', '/bpm', '/beat_conf',
        '/energy', '/energy_smooth',
        '/beat_energy', '/beat_energy_low', '/beat_energy_high',
        '/brightness', '/noisiness',
        '/bass_band', '/mid_band', '/high_band',
        '/dynamic_complexity'
    ]
    
    for addr in edm_features:
        disp.map(addr, capture_message)
    
    # Also map existing features
    for addr in ['/audio/levels', '/audio/spectrum', '/audio/beats', '/audio/bpm', '/audio/spectral']:
        disp.map(addr, capture_message)
    
    # Start OSC server
    server = osc_server.ThreadingOSCUDPServer(("127.0.0.1", 9001), disp)
    logger.info("OSC receiver started on port 9001")
    
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    
    # Create audio analyzer configuration
    config = AudioConfig(
        sample_rate=44100,
        block_size=512,
        osc_host="127.0.0.1",
        osc_port=9001,
        enable_essentia=True,  # Enable Essentia for full feature set
        enable_logging=False,
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
    logger.info("Generating mock audio data with beat simulation...")
    for i in range(20):
        # Create mock audio block with varying energy (simulate beats every 5 frames)
        t = np.linspace(0, config.block_size / config.sample_rate, config.block_size)
        
        # Simulate beat on frames 0, 5, 10, 15
        if i % 5 == 0:
            # Kick drum: 60Hz sine with amplitude burst
            freq = 60.0
            audio_block = 0.8 * np.sin(2 * np.pi * freq * t)
        else:
            # Background: lower amplitude 440Hz
            freq = 440.0
            audio_block = 0.3 * np.sin(2 * np.pi * freq * t)
        
        audio_block = audio_block.reshape(-1, 1)  # Mono
        
        # Process frame directly
        analyzer._process_frame(audio_block)
        
        time.sleep(0.01)  # Small delay to simulate real-time
    
    # Wait for messages to arrive
    time.sleep(0.5)
    
    # Verify received messages
    logger.info("\n=== EDM Feature Verification Results ===")
    
    all_ok = True
    
    # Check EDM features
    for addr in edm_features:
        if addr in received_messages:
            count = message_counts.get(addr, 0)
            values = received_messages[addr]
            logger.info(f"✓ {addr}: received {count} times, value={values[0]:.3f}")
            
            # Verify value is in [0, 1] range for normalized features
            if addr in ['/energy_smooth', '/brightness', '/noisiness', '/bass_band', '/mid_band', '/high_band']:
                if not (0 <= values[0] <= 1):
                    logger.warning(f"  ⚠ Value {values[0]} not in [0, 1] range")
        else:
            logger.error(f"✗ {addr}: NOT RECEIVED")
            all_ok = False
    
    # Check legacy features still work
    logger.info("\n=== Legacy Feature Verification ===")
    legacy_features = {
        '/audio/levels': 8,
        '/audio/spectrum': 32,
        '/audio/beats': 5,
        '/audio/bpm': 2,
        '/audio/spectral': 3,
    }
    
    for addr, expected_count in legacy_features.items():
        if addr in received_messages:
            values = received_messages[addr]
            logger.info(f"✓ {addr}: {len(values)} values")
            if len(values) != expected_count:
                logger.error(f"  ✗ Expected {expected_count} values, got {len(values)}")
                all_ok = False
        else:
            logger.error(f"✗ {addr}: NOT RECEIVED")
            all_ok = False
    
    # Stop server
    server.shutdown()
    
    if all_ok:
        logger.info("\n✓ All EDM feature tests PASSED")
        logger.info(f"Total features: {len(edm_features)} EDM + {len(legacy_features)} legacy = {len(edm_features) + len(legacy_features)}")
        return True
    else:
        logger.error("\n✗ Some EDM feature tests FAILED")
        return False


if __name__ == "__main__":
    success = test_edm_features()
    exit(0 if success else 1)
