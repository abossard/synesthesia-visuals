# WLED Sound Reactive Integration

Swift-VJ sends real-time audio analysis to WLED controllers via UDP Sound Sync v2 protocol.

## Quick Start

1. **Configure WLED** (v0.14+ required):
   - Enable "Sound Reactive"
   - Set "Audio Source" to "UDP Sound Sync"
   - Enable "Receive UDP Sound Sync"
   - Port: 21324

2. **Configure Swift-VJ**:
   - Open Settings → WLED
   - Click "Scan Network" to discover WLED devices (mDNS)
   - Or manually add controller (IP address)
   - Enable WLED Integration toggle
   - Adjust Update Rate (20-100 Hz) and FFT Smoothing (0.0-1.0)

3. **Start Swift-VJ** with Synesthesia running and play audio

## Protocol

WLED UDP Sound Sync v2 (port 21324):

- 40-byte binary packet
- Header: "00002\0" (6 bytes)
- Audio data: sampleRaw, sampleSmth, samplePeak (9 bytes)
- FFT spectrum: 16 bands, 0-255 per band (16 bytes)
- Metadata: FFT_Magnitude, FFT_MajorPeak (8 bytes)
- Floats: little-endian IEEE 754

## Configuration

**Global Settings:**

- Update Rate: Packets per second (20-100 Hz, default 50 Hz)
- FFT Smoothing: EMA smoothing factor (0.0-1.0, default 0.7)

**Controller Management:**

- Add: Manually enter IP or scan network (mDNS discovery)
- Enable/Disable: Toggle individual controllers
- Remove: Delete unwanted controllers

**Config file:** `~/Library/Application Support/SwiftVJ/wled-config.json`

## Audio Mapping

Swift-VJ receives 4 frequency bands from Synesthesia:

- Bass → WLED bands 0-3
- Low-Mid → WLED bands 4-7
- Mid → WLED bands 8-11
- Highs → WLED bands 12-15

## Troubleshooting

**No audio reaction:**

1. Check Settings → WLED: master toggle enabled, controllers enabled
2. Check logs: "WLED module started with X controllers"
3. Verify network: ping WLED IP, check firewall (UDP 21324)

**Intermittent failures:**

1. Check logs for "Failed to send to controllers"
2. Lower update rate to reduce network load
3. Increase FFT smoothing to reduce jitter

**WLED shows "No Audio":**

1. Verify WLED "Audio Source" is set to "UDP Sound Sync" (not Microphone)
2. Confirm "Receive UDP Sound Sync" is enabled
3. Check port is 21324

## Logging

All WLED logs prefixed with `[WLED]`:

- `[INFO] [WLED] WLED module started with 2 active controller(s)`
- `[DEBUG] [WLED]   → Living Room Strip (192.168.1.100:21324)`
- `[WARNING] [WLED] Failed to send to controllers: ...`

Filter in Log Viewer by searching "WLED".

## Technical Details

**Performance:**

- Packet size: 40 bytes
- Bandwidth: 16 Kbps per controller at 50 Hz
- CPU: < 1%
- Latency: < 20ms

**Network:**

- Protocol: UDP (stateless)
- Discovery: mDNS/Bonjour (_wled._tcp)
- Port: 21324 (configurable)

**Compatibility:**

- WLED v0.14.0+
- MoonModules WLED SR
- ESP32/ESP8266 hardware

## References

- [WLED Documentation](https://kno.wled.ge/)
- [UDP Sound Sync Protocol](https://mm.kno.wled.ge/WLEDSR/UDP-Sound-Sync/)
