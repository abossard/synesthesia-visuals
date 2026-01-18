# WLED Usage Examples

This directory contains example code for using WLED Sound Reactive integration in Swift-VJ.

## Overview

These examples demonstrate:
1. Basic WLED setup and configuration
2. Managing multiple WLED controllers
3. Manual packet creation and sending
4. Audio data simulation
5. Configuration persistence
6. Dynamic controller management

## Quick Start

```swift
import SwiftVJCore

// Create a WLED controller configuration
let controller = WLEDController(
    id: "my-strip",
    name: "My LED Strip",
    host: "192.168.1.100"
)

// Create WLED configuration
let config = WLEDConfig(
    controllers: [controller],
    enabled: true,
    updateRateHz: 50,
    fftSmoothing: 0.7
)

// Create and start module
let module = WLEDModule(config: config)
try await module.start()

// Update audio levels (called from OSC subscription)
let levels = OSCAudioLevels(
    bass: 0.8,
    lowMid: 0.6,
    mid: 0.5,
    highs: 0.4,
    level: 0.6
)
await module.updateAudioLevels(levels)

// Stop when done
await module.stop()
```

## Running Examples

Since these examples require network connectivity and WLED hardware, they are provided as reference documentation rather than executable code.

To use WLED in your own Swift-VJ application:

1. Import SwiftVJCore
2. Create WLEDController instances for your devices
3. Configure WLEDModule with your controllers
4. Start the module
5. Feed it audio data from Synesthesia OSC

See the [WLED Integration Guide](../docs/WLED_INTEGRATION.md) for complete setup instructions.
