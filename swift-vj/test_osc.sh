#!/bin/bash
# Test OSC messages for SwiftVJ development
# Requires: pip install python-osc

set -e

echo "=== SwiftVJ OSC Test Script ==="
echo ""
echo "This script sends test OSC messages to SwiftVJ on port 9000"
echo "Make sure SwiftVJ is running before executing this script"
echo ""

# Check if python-osc is installed
python3 -c "import pythonosc" 2>/dev/null || {
    echo "ERROR: python-osc not installed"
    echo "Install with: pip install python-osc"
    exit 1
}

# Check if SwiftVJ is listening
if ! lsof -i :9000 > /dev/null 2>&1; then
    echo "WARNING: No process listening on port 9000"
    echo "Make sure SwiftVJ is running: cd swift-vj && swift run SwiftVJ"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Sending test OSC messages..."
echo ""

# Send test messages
python3 << 'EOF'
from pythonosc import udp_client
import time

client = udp_client.SimpleUDPClient('127.0.0.1', 9000)

print("1. Testing /karaoke/track message...")
client.send_message('/karaoke/track', [
    1,                    # active
    'test',              # source
    'Test Artist',       # artist
    'Test Song Title',   # title
    'Test Album',        # album
    180.0,               # duration
    1                    # has_lyrics
])
time.sleep(0.5)

print("2. Testing /karaoke/pos message...")
client.send_message('/karaoke/pos', [30.0, 1])  # position, playing
time.sleep(0.5)

print("3. Testing /karaoke/lyrics/reset message...")
client.send_message('/karaoke/lyrics/reset', [])
time.sleep(0.5)

print("4. Testing /karaoke/lyrics/line messages...")
lyrics = [
    (0, 5.0, "First line of lyrics"),
    (1, 10.0, "Second line of lyrics"),
    (2, 15.0, "Third line of lyrics")
]
for idx, time_sec, text in lyrics:
    client.send_message('/karaoke/lyrics/line', [idx, time_sec, text])
    time.sleep(0.1)

print("5. Testing /karaoke/line/active message...")
client.send_message('/karaoke/line/active', [1])  # Activate second line
time.sleep(0.5)

print("6. Testing /karaoke/refrain/reset message...")
client.send_message('/karaoke/refrain/reset', [])
time.sleep(0.5)

print("7. Testing /karaoke/refrain/line messages...")
refrain_lyrics = [
    (0, 20.0, "Chorus line one"),
    (1, 25.0, "Chorus line two")
]
for idx, time_sec, text in refrain_lyrics:
    client.send_message('/karaoke/refrain/line', [idx, time_sec, text])
    time.sleep(0.1)

print("8. Testing /karaoke/refrain/active message...")
client.send_message('/karaoke/refrain/active', [0, "Chorus line one"])
time.sleep(0.5)

print("9. Testing /shader/load message...")
client.send_message('/shader/load', ['audio_reactive_gradient', 0.7, 0.5])
time.sleep(0.5)

print("10. Testing /audio/levels message (simulating audio reactivity)...")
# Simulate 10 seconds of varying audio levels
import math
for i in range(100):
    t = i / 10.0
    bass = 0.5 + 0.3 * math.sin(t * 2.0)
    mid = 0.4 + 0.2 * math.sin(t * 3.0)
    high = 0.3 + 0.3 * math.sin(t * 5.0)
    client.send_message('/audio/levels', [
        bass * 0.8,   # sub_bass
        bass,         # bass
        bass * 0.6,   # low_mid
        mid,          # mid
        mid * 0.8,    # high_mid
        high,         # presence
        high * 0.7,   # air
        0.5           # rms
    ])
    time.sleep(0.1)

print("\n✓ All test messages sent successfully!")
print("\nCheck SwiftVJ window and console output for results.")
EOF

echo ""
echo "=== Test Complete ==="
echo ""
echo "Check SwiftVJ for:"
echo "- Console logs showing received messages"
echo "- Song info displayed"
echo "- Lyrics text visible"
echo "- Shader responding to audio levels"
echo ""
