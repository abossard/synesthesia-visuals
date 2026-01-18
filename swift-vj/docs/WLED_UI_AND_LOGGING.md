# WLED UI and Logging Features

## Settings Panel

The WLED settings panel is accessible via **Settings → WLED** and provides comprehensive control over WLED Sound Reactive integration.

### Features

#### 1. Status Section
- **Master Enable/Disable Toggle**: Turn WLED integration on/off globally
- **Active Controllers Display**: Shows how many controllers are currently active
- Visual indicators:
  - Green checkmark icon when enabled
  - Gray circle when disabled
  - LED strip icon with active controller count

#### 2. Global Settings
- **Update Rate Slider** (20-100 Hz, default: 50 Hz)
  - Controls how often UDP packets are sent to WLED controllers
  - Lower rates reduce network traffic and CPU usage
  - Higher rates provide smoother, more responsive effects
  - Displays current value in Hz
  
- **FFT Smoothing Slider** (0.0-1.0, default: 0.7)
  - Controls smoothing of frequency spectrum data
  - Higher values = smoother but less responsive
  - Lower values = more responsive but may be jittery
  - Displays current value with 2 decimal precision

#### 3. Controllers Section

**Controller List:**
- Each controller row displays:
  - LED strip icon (filled when enabled, outline when disabled)
  - Controller name
  - IP address and port (e.g., "192.168.1.100:21324")
  - Enable/disable toggle switch
  - Delete button (trash icon)

**Empty State:**
- Shows when no controllers are configured
- Displays large LED strip icon
- "No WLED Controllers" message
- Helpful text: "Add controllers manually or scan your network"

**Add Controller:**
- Click "Add Controller" button with plus icon
- Opens modal dialog with fields:
  - **Name**: Descriptive name (e.g., "Living Room Strip")
  - **IP Address**: Controller's network IP (e.g., "192.168.1.100")
  - **Port**: UDP port (default: 21324)
- Validation: Name and IP address required
- Cancel or Add buttons

**Network Scan:**
- Click "Scan Network" button with antenna icon
- Button shows spinner while scanning
- Discovers WLED devices on local network (future feature)
- Discovered devices shown in footer with "Add" buttons
- Currently shows scanning animation (implementation pending)

### User Interactions

1. **Enabling WLED Integration:**
   - Toggle master switch ON
   - Log entry: "WLED integration enabled with X active controller(s)"

2. **Adding a Controller:**
   - Click "Add Controller"
   - Fill in name and IP address
   - Click "Add"
   - Log entry: "Added WLED controller: [name] ([host]:[port])"

3. **Enabling/Disabling a Controller:**
   - Toggle switch on controller row
   - Log entry: "WLED controller [name] enabled/disabled"

4. **Removing a Controller:**
   - Click trash icon
   - Controller immediately removed
   - Log entry: "Removed WLED controller: [name]"

5. **Adjusting Settings:**
   - Move update rate slider
   - Configuration auto-saved
   - Settings applied immediately to running module

6. **Scanning Network:**
   - Click "Scan Network"
   - Button disables and shows spinner
   - Log entry: "Scanning network for WLED devices..."
   - On completion: "Network scan complete. Found X devices."

## Logging Integration

### Log Messages

The WLED module generates detailed log entries for monitoring and troubleshooting:

#### Startup/Shutdown

```
[INFO] [WLED] Starting WLED module...
[DEBUG] [WLED] WLED adapter started
[DEBUG] [WLED] Subscribed to audio OSC messages
[INFO] [WLED] WLED module started with 2 active controller(s)
[DEBUG] [WLED]   → Living Room Strip (192.168.1.100:21324)
[DEBUG] [WLED]   → DJ Booth Strip (192.168.1.101:21324)
```

**No Controllers:**
```
[WARNING] [WLED] WLED module started but no controllers are enabled
```

**Shutdown:**
```
[INFO] [WLED] Stopping WLED module...
[INFO] [WLED] WLED module stopped. Sent 15420 packets, 3 failed.
```

#### Configuration Changes

**Controller Added:**
```
[INFO] [WLED] Added WLED controller: Bedroom Strip (192.168.1.102:21324)
```

**Controller Removed:**
```
[INFO] [WLED] Removed WLED controller: Bedroom Strip
```

**Controller Toggled:**
```
[INFO] [WLED] WLED controller Living Room Strip enabled
[INFO] [WLED] WLED controller DJ Booth Strip disabled
```

**Configuration Updated:**
```
[INFO] [WLED] WLED configuration updated: 3 active controller(s)
[INFO] [WLED] Active controllers changed: 2 → 3
[DEBUG] [WLED] Update loop restarted with new settings
```

**Integration Toggled:**
```
[INFO] [WLED] WLED integration enabled with 2 active controller(s)
[WARNING] [WLED] WLED integration disabled
```

#### Runtime Errors

**Send Failures:**
```
[WARNING] [WLED] Failed to send to controllers: Living Room Strip, DJ Booth Strip
```

**Network Issues:**
```
[ERROR] [WLED] Connection failed: 192.168.1.100 - Network unreachable
[ERROR] [WLED] Connection timeout: 192.168.1.101
```

### Viewing Logs

1. **Log Viewer Tab:**
   - Access via main window's "Logs" tab
   - Shows all application logs including WLED
   - Filter by level: DEBUG, INFO, WARN, ERROR
   - Search for "WLED" to see only WLED-related logs
   - Auto-scroll option to follow live logs

2. **Log Levels:**
   - **DEBUG** (blue): Detailed operational info (adapter start, OSC subscription)
   - **INFO** (white): Normal operations (start/stop, config changes)
   - **WARN** (yellow): Warnings (disabled integration, no controllers)
   - **ERROR** (red): Errors (connection failures, send errors)

3. **Filtering WLED Logs:**
   - Use search box: type "WLED"
   - All WLED messages prefixed with `[WLED]`
   - Easy to isolate WLED-specific activity

### Status Monitoring

The module provides detailed runtime statistics via `getStatus()`:

```swift
{
    "started": true,
    "enabled": true,
    "controllers": 3,
    "controllersActive": 2,
    "updateRateHz": 50,
    "fftSmoothing": 0.7,
    "packetsProcessed": 15423,
    "packetsSent": 30842,  // 2 controllers × 15421 packets
    "packetsFailed": 4,
    "successRate": 0.9998,
    "lastUpdateTime": "2026-01-18T17:00:00Z",
    "secondsSinceLastUpdate": 0.02,
    "adapter": {
        "started": true,
        "connections": 2,
        "packetsSent": 30842,
        "sendErrors": 4,
        "lastSendTime": "2026-01-18T17:00:00Z"
    }
}
```

This status data can be displayed in a future debug/monitoring panel.

## Future Enhancements

### Network Discovery
- **mDNS/Bonjour**: Automatic discovery of WLED devices on network
- **Device Info**: Show WLED version, LED count, current effect
- **One-Click Add**: Directly add discovered devices
- **Refresh Button**: Re-scan network

### Controller Status Indicators
- **Connection Status**: Green/yellow/red indicator per controller
- **Packet Rate**: Real-time packets/second display
- **Error Count**: Show failed packet count
- **Last Seen**: Time since last successful send

### Advanced Settings
- **Per-Controller Settings**: Individual update rates, FFT smoothing
- **Priority Levels**: Prioritize certain controllers over others
- **Compression**: Optional packet compression for WiFi
- **Multicast**: Send one packet to multiple controllers

### Debug Panel
- **Live FFT Visualization**: See spectrum being sent in real-time
- **Packet Inspector**: View raw packet data
- **Performance Metrics**: CPU usage, latency, bandwidth
- **Connection Test**: Ping each controller, show RTT

### Presets
- **Save/Load Configurations**: Quick switching between setups
- **Scene-Based Config**: Different WLED setups for different venues
- **Import/Export**: Share configurations

## Troubleshooting via UI

### No Audio Reaction

1. Check Settings → WLED:
   - Is master toggle enabled?
   - Are controllers enabled?
   - Are IP addresses correct?

2. Check Logs:
   - Search for "WLED"
   - Look for "started with X active controllers"
   - Check for error messages

3. Verify Network:
   - Ping controller IPs from terminal
   - Check firewall settings (UDP port 21324)

### Intermittent Failures

1. Check Logs for patterns:
   - Search for "Failed to send"
   - Note which controllers fail
   - Check if correlated with network activity

2. Adjust Settings:
   - Lower update rate (reduce network load)
   - Increase FFT smoothing (reduce jitter)

3. Check Statistics:
   - Success rate should be > 99%
   - If lower, investigate network issues

### Configuration Not Saving

1. Check file permissions:
   - `~/Library/Application Support/SwiftVJ/`
   - Should be writable by user

2. Check Logs:
   - Look for "configuration saved" messages
   - Check for file I/O errors

## Keyboard Shortcuts

Future shortcuts for WLED panel:
- `⌘ + W`: Toggle WLED integration
- `⌘ + N`: Add new controller
- `⌘ + R`: Refresh/scan network
- `⌘ + ,`: Open WLED settings

## Accessibility

- All controls are keyboard accessible
- Tab navigation through form fields
- VoiceOver support for all UI elements
- High contrast mode compatible
- Screen reader announces status changes

## Best Practices

1. **Add controllers with static IPs**: Avoid DHCP lease changes
2. **Test with one controller first**: Verify connectivity before adding more
3. **Monitor logs during setup**: Watch for errors in real-time
4. **Use descriptive names**: "Living Room Strip" not "WLED1"
5. **Start with default settings**: Adjust only if needed
6. **Check "Scan Network" occasionally**: Find new devices

## Integration with App

The WLED settings panel integrates seamlessly with Swift-VJ:

1. **Settings Window**: Accessed via Settings menu or `⌘ ,`
2. **Tab-Based UI**: WLED is one tab among General, Paths, OSC, About
3. **Live Updates**: Changes apply immediately to running module
4. **Persistent Config**: Saved to disk, loaded on app start
5. **State Synchronization**: UI reflects current module state

## Example Workflow

### First-Time Setup

1. Open Settings → WLED tab
2. Click "Add Controller"
3. Enter name: "Main Strip"
4. Enter IP: "192.168.1.100"
5. Click "Add"
6. Toggle master switch ON
7. Check logs for "WLED module started"
8. Play audio in Synesthesia
9. Verify LEDs react to audio

### Adding Multiple Controllers

1. Add first controller (see above)
2. Click "Add Controller" again
3. Enter second controller details
4. Repeat for all controllers
5. Verify in log: "started with X active controllers"
6. Individual toggles allow selective enable/disable

### Troubleshooting Failed Controller

1. Check logs for specific controller errors
2. Disable failing controller temporarily
3. Verify other controllers still work
4. Fix network issue with failing controller
5. Re-enable controller
6. Check logs for successful connection

This comprehensive UI and logging system makes WLED integration easy to set up, monitor, and troubleshoot.
