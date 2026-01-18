// WLED Types - Domain data for WLED Sound Reactive integration
// Following Grokking Simplicity: immutable data types

import Foundation

// MARK: - WLED Audio Sync Packet (v2)

/// WLED UDP Sound Sync packet structure (v2, WLED 0.14+)
/// Used to transmit audio analysis data to WLED devices
/// Port: 21324 (default, configurable)
/// Size: 40 bytes
///
/// Reference: https://mm.kno.wled.ge/WLEDSR/UDP-Sound-Sync/
public struct WLEDAudioSyncPacket: Sendable, Equatable {
    /// Protocol header - always "00002" for v2
    public static let headerV2: String = "00002"
    
    /// Raw audio sample amplitude (float, typically 0.0-1.0)
    public let sampleRaw: Float
    
    /// Smoothed audio sample amplitude (float, typically 0.0-1.0)
    public let sampleSmth: Float
    
    /// Peak detection flag (0 = no peak, 1 = peak detected)
    public let samplePeak: UInt8
    
    /// Reserved for future use (e.g., loudness)
    public let reserved1: UInt8
    
    /// FFT spectrum data (16 frequency bands, 0-255 per band)
    /// Index 0 = lowest frequency, index 15 = highest frequency
    public let fftResult: [UInt8]
    
    /// Magnitude of the strongest FFT peak
    public let fftMagnitude: Float
    
    /// Frequency bin index of the major peak
    public let fftMajorPeak: Float
    
    // MARK: - Initialization
    
    public init(
        sampleRaw: Float = 0,
        sampleSmth: Float = 0,
        samplePeak: UInt8 = 0,
        reserved1: UInt8 = 0,
        fftResult: [UInt8] = Array(repeating: 0, count: 16),
        fftMagnitude: Float = 0,
        fftMajorPeak: Float = 0
    ) {
        self.sampleRaw = sampleRaw
        self.sampleSmth = sampleSmth
        self.samplePeak = samplePeak
        self.reserved1 = reserved1
        // Ensure exactly 16 bands
        if fftResult.count == 16 {
            self.fftResult = fftResult
        } else {
            var bands = fftResult
            bands.resize(to: 16, defaultValue: 0)
            self.fftResult = bands
        }
        self.fftMagnitude = fftMagnitude
        self.fftMajorPeak = fftMajorPeak
    }
    
    /// Create a silent packet (all zeros)
    public static var silent: WLEDAudioSyncPacket {
        WLEDAudioSyncPacket()
    }
    
    // MARK: - Binary Encoding
    
    /// Encode packet to binary data for UDP transmission
    /// Total size: 40 bytes (6 + 4 + 4 + 1 + 1 + 16 + 4 + 4)
    public func encode() -> Data {
        var data = Data()
        
        // Header: "00002" + null terminator (6 bytes)
        let headerBytes = Self.headerV2.utf8 + [0]
        data.append(contentsOf: headerBytes)
        
        // sampleRaw: Float (4 bytes, little-endian)
        data.append(sampleRaw.bytes)
        
        // sampleSmth: Float (4 bytes, little-endian)
        data.append(sampleSmth.bytes)
        
        // samplePeak: UInt8 (1 byte)
        data.append(samplePeak)
        
        // reserved1: UInt8 (1 byte)
        data.append(reserved1)
        
        // fftResult: 16 x UInt8 (16 bytes)
        data.append(contentsOf: fftResult)
        
        // FFT_Magnitude: Float (4 bytes, little-endian)
        data.append(fftMagnitude.bytes)
        
        // FFT_MajorPeak: Float (4 bytes, little-endian)
        data.append(fftMajorPeak.bytes)
        
        return data
    }
}

// MARK: - WLED Controller Configuration

/// Configuration for a single WLED controller
public struct WLEDController: Sendable, Equatable, Codable {
    /// Unique identifier for this controller
    public let id: String
    
    /// Human-readable label
    public let name: String
    
    /// IP address or hostname
    public let host: String
    
    /// UDP port for audio sync (default: 21324)
    public let port: UInt16
    
    /// Whether this controller is enabled
    public let enabled: Bool
    
    public init(
        id: String,
        name: String,
        host: String,
        port: UInt16 = 21324,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.enabled = enabled
    }
}

// MARK: - WLED Configuration

/// Configuration for WLED integration
public struct WLEDConfig: Sendable, Equatable, Codable {
    /// List of WLED controllers to send audio data to
    public let controllers: [WLEDController]
    
    /// Whether WLED integration is enabled globally
    public let enabled: Bool
    
    /// Update rate in Hz (e.g., 50 Hz = 20ms between packets)
    public let updateRateHz: Int
    
    /// FFT smoothing factor (0.0-1.0, higher = smoother)
    public let fftSmoothing: Float
    
    public init(
        controllers: [WLEDController] = [],
        enabled: Bool = false,
        updateRateHz: Int = 50,
        fftSmoothing: Float = 0.7
    ) {
        self.controllers = controllers
        self.enabled = enabled
        self.updateRateHz = updateRateHz
        self.fftSmoothing = fftSmoothing
    }
    
    /// Create default config with example controllers
    public static var `default`: WLEDConfig {
        WLEDConfig(
            controllers: [
                WLEDController(
                    id: "wled-1",
                    name: "WLED Strip 1",
                    host: "192.168.1.100",
                    enabled: false
                )
            ],
            enabled: false,
            updateRateHz: 50,
            fftSmoothing: 0.7
        )
    }
}

// MARK: - Helper Extensions

private extension Array {
    mutating func resize(to size: Int, defaultValue: Element) {
        if count < size {
            self.append(contentsOf: Array(repeating: defaultValue, count: size - count))
        } else if count > size {
            self = Array(self.prefix(size))
        }
    }
}

private extension Float {
    /// Convert Float to little-endian bytes
    var bytes: [UInt8] {
        withUnsafeBytes(of: self.bitPattern.littleEndian) { Array($0) }
    }
}
