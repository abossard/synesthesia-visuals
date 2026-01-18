# WLED Sound Reactive Integration

Swift-VJ can send real-time audio analysis data to WLED (Wireless LED) controllers, enabling audio-reactive LED effects synchronized with your VJ setup.

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Setup Guide](#setup-guide)
4. [Configuration](#configuration)
5. [Supported Features](#supported-features)
6. [Troubleshooting](#troubleshooting)
7. [Technical Details](#technical-details)

---

## Overview

WLED Sound Reactive is a feature in WLED firmware (v0.14+) that allows LED strips to respond to audio in real-time. Swift-VJ integrates with WLED by:

1. Receiving audio analysis from Synesthesia via OSC (port 9999)
2. Processing audio levels, FFT spectrum, and beat detection
3. Encoding data into WLED's UDP Sound Sync protocol (v2)
4. Broadcasting packets to multiple WLED controllers (port 21324)

**Benefits:**
- **Synchronized visuals**: LED strips react in perfect sync with your projected visuals
- **No microphone needed**: WLED controllers don't need their own microphones
- **Multiple controllers**: Support for unlimited WLED devices on your network
- **High quality**: Uses Synesthesia's professional audio analysis
- **Low latency**: UDP packets sent at 50 Hz (20ms intervals)

---

## How It Works

### Architecture

```
┌─────────────────┐
│  Synesthesia    │  Audio analysis
│  (Audio In)     │
└────────┬────────┘
         │ OSC (port 9999)
         │ /syn/level/bass, /syn/level/mid, etc.
         ▼
┌─────────────────┐
│   Swift-VJ      │  Audio processing
│   OSCHub        │  - Receives OSC messages
│   AudioState    │  - Processes audio levels
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  WLEDModule     │  Packet creation
│                 │  - Maps 4 bands → 16 bands
│                 │  - Applies FFT smoothing
│                 │  - Creates UDP packets
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  WLEDAdapter    │  UDP transmission
│                 │  - Sends to multiple IPs
│                 │  - Manages connections
└────────┬────────┘
         │ UDP (port 21324)
         │ Binary packets (40 bytes)
         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  WLED Device 1  │     │  WLED Device 2  │     │  WLED Device 3  │
│  192.168.1.100  │     │  192.168.1.101  │     │  192.168.1.102  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Audio Data Flow

1. **Synesthesia** analyzes audio from your audio interface (BlackHole, etc.)
2. **Swift-VJ** receives 4-band audio levels via OSC:
   - Bass (sub-bass + bass)
   - Low-mid
   - Mid
   - Highs
3. **WLEDModule** transforms audio data:
   - Maps 4 bands → 16 FFT bands (WLED expects 16)
   - Applies exponential moving average (EMA) smoothing
   - Detects peaks (bass hits)
   - Calculates magnitude and major peak
4. **WLEDAdapter** sends UDP packets to all enabled controllers

---

## Setup Guide

### Prerequisites

1. **WLED Controllers**: ESP32 or ESP8266 with WLED firmware v0.14+
2. **Network**: WLED devices on same network as your Mac
3. **Swift-VJ**: Running and receiving audio from Synesthesia
4. **Synesthesia**: Sending OSC audio data on port 9999

### Step 1: Find Your WLED IP Addresses

1. Open WLED web interface (usually `http://wled-xxxxx.local`)
2. Go to **Config → WiFi Setup**
3. Note the IP address (e.g., `192.168.1.100`)
4. Repeat for each WLED controller

### Step 2: Enable UDP Sound Sync on WLED

For each WLED controller:

1. Open WLED web interface
2. Go to **Config → Sound Settings**
3. Enable **Sound Reactive**
4. Set **Receive UDP Sound Sync** to **ON**
5. Set **UDP Port** to **21324** (default)
6. **Important**: Set **Audio Source** to **UDP Sound Sync** (not Microphone)
7. Click **Save**

### Step 3: Configure Swift-VJ

#### Option A: Using the GUI (Recommended)

1. Open Swift-VJ app
2. Go to **Settings → WLED Integration**
3. Click **Add Controller**
4. Enter:
   - **Name**: Descriptive name (e.g., "Front Strip")
   - **IP Address**: WLED IP (e.g., `192.168.1.100`)
   - **Port**: `21324` (default)
   - **Enabled**: Check to enable
5. Repeat for each controller
6. Set **Update Rate**: `50 Hz` (recommended)
7. Set **FFT Smoothing**: `0.7` (adjust for responsiveness)
8. Enable **WLED Integration** (master switch)
9. Click **Save**

#### Option B: Manual Configuration

Edit `~/Library/Application Support/SwiftVJ/wled-config.json`:

```json
{
  "controllers": [
    {
      "id": "wled-1",
      "name": "Front Strip",
      "host": "192.168.1.100",
      "port": 21324,
      "enabled": true
    },
    {
      "id": "wled-2",
      "name": "Back Strip",
      "host": "192.168.1.101",
      "port": 21324,
      "enabled": true
    }
  ],
  "enabled": true,
  "updateRateHz": 50,
  "fftSmoothing": 0.7
}
```

### Step 4: Test the Connection

1. Start Swift-VJ
2. Play audio in Synesthesia
3. Check Swift-VJ logs: `WLEDModule started with X active controllers`
4. Open WLED web interface → **Info**
5. Verify **UDP Sound Sync** shows **receiving packets**
6. LED effects should react to audio

---

## Configuration

### WLED Controller Settings

| Setting | Description | Default | Notes |
|---------|-------------|---------|-------|
| **id** | Unique identifier | `wled-1` | Used internally |
| **name** | Display name | `WLED Strip 1` | Shown in UI |
| **host** | IP address or hostname | `192.168.1.100` | Static IP recommended |
| **port** | UDP port | `21324` | WLED standard port |
| **enabled** | Enable/disable this controller | `true` | Can disable without removing |

### Global Settings

| Setting | Description | Default | Range | Notes |
|---------|-------------|---------|-------|-------|
| **enabled** | Master on/off switch | `false` | - | Disables all controllers |
| **updateRateHz** | Packets per second | `50` | 20-100 | Higher = smoother, more CPU |
| **fftSmoothing** | FFT smoothing factor | `0.7` | 0.0-1.0 | Higher = smoother, less responsive |

### Recommended Settings

| Scenario | updateRateHz | fftSmoothing |
|----------|--------------|--------------|
| **Low-energy ambient** | 30 | 0.85 |
| **Balanced (default)** | 50 | 0.70 |
| **High-energy/responsive** | 60 | 0.50 |
| **Maximum responsiveness** | 100 | 0.30 |

---

## Supported Features

### Audio Data

Swift-VJ sends the following audio data to WLED:

| Field | Source | Description |
|-------|--------|-------------|
| **sampleRaw** | `level` | Overall audio amplitude (0-1) |
| **sampleSmth** | `level * 0.7 + bassPresence * 0.3` | Smoothed amplitude |
| **samplePeak** | `hitsBass > 0.5` | Bass hit detection (0 or 1) |
| **fftResult[16]** | 4 bands → 16 bands | FFT spectrum (0-255 per band) |
| **FFT_Magnitude** | `max(fftResult)` | Strongest frequency magnitude |
| **FFT_MajorPeak** | `argmax(fftResult)` | Index of dominant frequency |

### Frequency Band Mapping

Swift-VJ receives 4 bands from Synesthesia and maps them to WLED's 16 bands:

```
Synesthesia (4 bands)          WLED (16 bands)
┌──────────────────┐           ┌──────────────────┐
│ Bass             │  ───────▶ │ Bands 0-3        │
│ Low-Mid          │  ───────▶ │ Bands 4-7        │
│ Mid              │  ───────▶ │ Bands 8-11       │
│ Highs            │  ───────▶ │ Bands 12-15      │
└──────────────────┘           └──────────────────┘
```

Each source band is replicated across 4 WLED bands, with EMA smoothing applied.

### WLED Effect Compatibility

All WLED Sound Reactive effects are supported:

- ✅ Volume reactive effects (use `sampleRaw`, `sampleSmth`)
- ✅ Beat reactive effects (use `samplePeak`)
- ✅ Frequency reactive effects (use `fftResult[]`)
- ✅ Custom effects (full packet available)

---

## Troubleshooting

### No WLED Reaction

**Check:**
1. Is WLED receiving packets?
   - Open WLED web interface → **Info**
   - Look for "UDP Sound Sync: receiving"
2. Is Swift-VJ sending packets?
   - Check Swift-VJ logs for `WLEDModule started with X active controllers`
   - Verify `X > 0` (at least one enabled controller)
3. Is Synesthesia sending audio OSC?
   - Check OSC Debug view in Swift-VJ
   - Should see `/syn/level/bass`, `/syn/level/mid`, etc.
4. Network connectivity
   - Ping WLED IP: `ping 192.168.1.100`
   - Check firewall settings (macOS may block UDP)

### WLED Shows "No Audio" or "Timeout"

**Cause:** WLED not receiving UDP packets for 1-2 seconds.

**Solutions:**
1. Check WLED **Audio Source** is set to **UDP Sound Sync** (not Microphone)
2. Verify **Receive UDP Sound Sync** is enabled
3. Confirm **UDP Port** is `21324`
4. Restart WLED controller
5. Check network latency: `ping -c 10 192.168.1.100`

### Effects Too Slow/Laggy

**Cause:** Low update rate or high FFT smoothing.

**Solutions:**
1. Increase **updateRateHz** to `60` or `100`
2. Decrease **fftSmoothing** to `0.5` or `0.3`
3. Reduce network congestion (fewer devices on WiFi)

### Effects Too Jittery/Noisy

**Cause:** High update rate or low FFT smoothing.

**Solutions:**
1. Decrease **updateRateHz** to `30` or `40`
2. Increase **fftSmoothing** to `0.8` or `0.9`

### Only Some Controllers Work

**Check:**
1. Individual controller **enabled** setting
2. Correct IP addresses (use static IPs, not DHCP)
3. Network connectivity to each device
4. WLED firmware version (v0.14+ required)

### High CPU Usage

**Cause:** Too many controllers or high update rate.

**Solutions:**
1. Reduce **updateRateHz** (50 Hz is usually sufficient)
2. Disable unused controllers
3. Use multicast instead of unicast (future feature)

---

## Technical Details

### UDP Sound Sync Protocol v2

Swift-VJ implements WLED's UDP Sound Sync protocol v2 (WLED 0.14+).

**Packet Structure (40 bytes):**

```c
struct audioSyncPacket_v2 {
  char header[6];        // "00002\0"
  float sampleRaw;       // 4 bytes (little-endian IEEE 754)
  float sampleSmth;      // 4 bytes (little-endian IEEE 754)
  uint8_t samplePeak;    // 1 byte (0 or 1)
  uint8_t reserved1;     // 1 byte (reserved, set to 0)
  uint8_t fftResult[16]; // 16 bytes (one per frequency band)
  float FFT_Magnitude;   // 4 bytes (little-endian IEEE 754)
  float FFT_MajorPeak;   // 4 bytes (little-endian IEEE 754)
};
```

**Binary Layout:**

| Offset | Size | Field | Type | Notes |
|--------|------|-------|------|-------|
| 0 | 6 | header | string | Always "00002\0" |
| 6 | 4 | sampleRaw | float | Little-endian |
| 10 | 4 | sampleSmth | float | Little-endian |
| 14 | 1 | samplePeak | uint8 | 0 or 1 |
| 15 | 1 | reserved1 | uint8 | Set to 0 |
| 16 | 16 | fftResult | uint8[16] | 0-255 per band |
| 32 | 4 | FFT_Magnitude | float | Little-endian |
| 36 | 4 | FFT_MajorPeak | float | Little-endian |

### Performance

| Metric | Value | Notes |
|--------|-------|-------|
| **Packet size** | 40 bytes | Fixed size |
| **Update rate** | 50 Hz (default) | 20ms between packets |
| **Bandwidth (1 controller)** | ~16 Kbps | 40 bytes × 50 Hz × 8 bits |
| **Bandwidth (10 controllers)** | ~160 Kbps | Linear scaling |
| **Latency** | < 20ms | UDP + processing time |
| **CPU usage** | < 1% | Minimal impact |

### Network Requirements

- **Protocol**: UDP (User Datagram Protocol)
- **Port**: 21324 (default, configurable)
- **Transport**: Unicast (one packet per controller)
- **No multicast**: Current implementation sends separate packets
- **Firewall**: May need to allow outgoing UDP on port 21324

### Code Architecture

Following Swift-VJ design principles:

**Domain Types** (`WLEDTypes.swift`):
- `WLEDAudioSyncPacket` - Immutable packet structure
- `WLEDController` - Controller configuration (Codable)
- `WLEDConfig` - Global settings (Codable)

**Adapter** (`WLEDAdapter.swift`):
- Deep module pattern (3 public methods)
- Hides Network.framework complexity
- Manages UDP connections per controller

**Module** (`WLEDModule.swift`):
- Implements `Module` protocol (start/stop/getStatus)
- Subscribes to Synesthesia audio OSC
- Periodic update loop (configurable rate)
- Pure function for packet creation

**Pure Functions**:
- `createPacket()` - Audio state → WLED packet
- `createFFTBands()` - 4 bands → 16 bands with smoothing
- `encode()` - Packet → binary data

### Future Enhancements

Planned features for future releases:

- [ ] **Multicast support** - Send one packet to multiple controllers
- [ ] **WLED discovery** - Auto-detect WLED devices on network
- [ ] **Preset sync** - Change WLED effects based on song mood/energy
- [ ] **Beat quantization** - Snap peak detection to BPM grid
- [ ] **Custom band mapping** - User-defined frequency ranges
- [ ] **Compression** - Optional packet compression for WiFi optimization
- [ ] **Statistics dashboard** - Monitor packet loss, latency, throughput

---

## References

- [WLED Documentation](https://kno.wled.ge/)
- [WLED Sound Reactive](https://kno.wled.ge/advanced/audio-reactive/)
- [UDP Sound Sync Protocol](https://mm.kno.wled.ge/WLEDSR/UDP-Sound-Sync/)
- [MoonModules WLED SR](https://mm.kno.wled.ge/)

---

## Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review WLED logs in web interface
3. Check Swift-VJ logs for error messages
4. Verify network connectivity
5. Test with WLED's built-in microphone first
6. Open an issue on GitHub with:
   - WLED firmware version
   - Swift-VJ version
   - Network topology
   - Error messages/logs
