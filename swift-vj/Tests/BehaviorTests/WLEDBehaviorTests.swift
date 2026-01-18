// WLED Behavior Tests - Pure function tests for WLED packet creation
// Following TDD philosophy: test behaviors, not implementation

import XCTest
@testable import SwiftVJCore

final class WLEDBehaviorTests: XCTestCase {
    
    // MARK: - Packet Encoding Tests
    
    func testSilentPacketEncoding() {
        // GIVEN: A silent audio packet
        let packet = WLEDAudioSyncPacket.silent
        
        // WHEN: Encoding to binary data
        let data = packet.encode()
        
        // THEN: Should produce 40 bytes
        XCTAssertEqual(data.count, 40, "Packet should be exactly 40 bytes")
        
        // THEN: Header should be "00002\0"
        let header = String(data: data.prefix(6), encoding: .utf8)
        XCTAssertEqual(header, "00002\0")
        
        // THEN: All values should be zero
        XCTAssertEqual(packet.sampleRaw, 0)
        XCTAssertEqual(packet.sampleSmth, 0)
        XCTAssertEqual(packet.samplePeak, 0)
        XCTAssertEqual(packet.fftMagnitude, 0)
    }
    
    func testPacketEncodingWithAudioData() {
        // GIVEN: A packet with audio data
        let fftBands: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160]
        let packet = WLEDAudioSyncPacket(
            sampleRaw: 0.75,
            sampleSmth: 0.65,
            samplePeak: 1,
            reserved1: 0,
            fftResult: fftBands,
            fftMagnitude: 0.9,
            fftMajorPeak: 8.0
        )
        
        // WHEN: Encoding to binary data
        let data = packet.encode()
        
        // THEN: Should produce 40 bytes
        XCTAssertEqual(data.count, 40)
        
        // THEN: Header should be correct
        let headerData = data.prefix(6)
        let header = String(data: headerData, encoding: .utf8)
        XCTAssertEqual(header, "00002\0")
        
        // THEN: Sample peak should be 1
        let peakByte = data[14] // After header (6) + 2 floats (8)
        XCTAssertEqual(peakByte, 1)
        
        // THEN: FFT bands should be present
        let fftData = Array(data[16..<32]) // 16 bytes starting at offset 16
        XCTAssertEqual(fftData, fftBands)
    }
    
    func testFFTBandClipping() {
        // GIVEN: FFT bands with too many values
        let tooManyBands: [UInt8] = Array(repeating: 100, count: 20)
        let packet = WLEDAudioSyncPacket(fftResult: tooManyBands)
        
        // THEN: Should clip to 16 bands
        XCTAssertEqual(packet.fftResult.count, 16)
        
        // GIVEN: FFT bands with too few values
        let tooFewBands: [UInt8] = [10, 20, 30]
        let packet2 = WLEDAudioSyncPacket(fftResult: tooFewBands)
        
        // THEN: Should pad to 16 bands
        XCTAssertEqual(packet2.fftResult.count, 16)
        XCTAssertEqual(packet2.fftResult[0], 10)
        XCTAssertEqual(packet2.fftResult[1], 20)
        XCTAssertEqual(packet2.fftResult[2], 30)
        XCTAssertEqual(packet2.fftResult[3], 0)
    }
    
    // MARK: - Configuration Tests
    
    func testWLEDControllerCreation() {
        // GIVEN: Controller configuration
        let controller = WLEDController(
            id: "test-1",
            name: "Test Strip",
            host: "192.168.1.100",
            port: 21324,
            enabled: true
        )
        
        // THEN: Should have correct values
        XCTAssertEqual(controller.id, "test-1")
        XCTAssertEqual(controller.name, "Test Strip")
        XCTAssertEqual(controller.host, "192.168.1.100")
        XCTAssertEqual(controller.port, 21324)
        XCTAssertTrue(controller.enabled)
    }
    
    func testWLEDControllerDefaultPort() {
        // GIVEN: Controller without explicit port
        let controller = WLEDController(
            id: "test-1",
            name: "Test Strip",
            host: "192.168.1.100"
        )
        
        // THEN: Should use default port 21324
        XCTAssertEqual(controller.port, 21324)
    }
    
    func testWLEDConfigDefault() {
        // GIVEN: Default WLED config
        let config = WLEDConfig.default
        
        // THEN: Should have sensible defaults
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.updateRateHz, 50)
        XCTAssertEqual(config.fftSmoothing, 0.7)
        XCTAssertEqual(config.controllers.count, 1)
    }
    
    func testWLEDConfigCodable() throws {
        // GIVEN: WLED configuration
        let controller = WLEDController(
            id: "test-1",
            name: "Test Strip",
            host: "192.168.1.100"
        )
        let config = WLEDConfig(
            controllers: [controller],
            enabled: true,
            updateRateHz: 60,
            fftSmoothing: 0.8
        )
        
        // WHEN: Encoding to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        // WHEN: Decoding from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WLEDConfig.self, from: data)
        
        // THEN: Should match original
        XCTAssertEqual(decoded.controllers.count, 1)
        XCTAssertEqual(decoded.controllers[0].id, "test-1")
        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.updateRateHz, 60)
        XCTAssertEqual(decoded.fftSmoothing, 0.8)
    }
    
    // MARK: - Packet Size Verification
    
    func testPacketSizeConsistency() {
        // Test multiple packets to ensure consistent size
        let packets = [
            WLEDAudioSyncPacket.silent,
            WLEDAudioSyncPacket(sampleRaw: 0.5, sampleSmth: 0.5),
            WLEDAudioSyncPacket(
                sampleRaw: 1.0,
                sampleSmth: 0.9,
                samplePeak: 1,
                fftResult: Array(repeating: 255, count: 16),
                fftMagnitude: 1.0,
                fftMajorPeak: 15.0
            )
        ]
        
        for (index, packet) in packets.enumerated() {
            let data = packet.encode()
            XCTAssertEqual(
                data.count,
                40,
                "Packet \(index) should be exactly 40 bytes, got \(data.count)"
            )
        }
    }
    
    // MARK: - Binary Format Verification
    
    func testBinaryFormatLittleEndian() {
        // GIVEN: Packet with known float values
        let packet = WLEDAudioSyncPacket(
            sampleRaw: 1.0,  // 0x3F800000 in IEEE 754
            sampleSmth: 0.5  // 0x3F000000 in IEEE 754
        )
        
        // WHEN: Encoding
        let data = packet.encode()
        
        // THEN: Floats should be little-endian
        // sampleRaw starts at byte 6
        let rawBytes = Array(data[6..<10])
        // Little-endian representation of 1.0 = [0x00, 0x00, 0x80, 0x3F]
        XCTAssertEqual(rawBytes, [0x00, 0x00, 0x80, 0x3F])
        
        // sampleSmth starts at byte 10
        let smthBytes = Array(data[10..<14])
        // Little-endian representation of 0.5 = [0x00, 0x00, 0x00, 0x3F]
        XCTAssertEqual(smthBytes, [0x00, 0x00, 0x00, 0x3F])
    }
    
    // MARK: - Edge Cases
    
    func testNegativeValuesClampedToZero() {
        // Note: The current implementation doesn't clamp, but the API should
        // accept normalized 0-1 values. This test documents the behavior.
        let packet = WLEDAudioSyncPacket(
            sampleRaw: -0.5,
            sampleSmth: -1.0
        )
        
        // Values are stored as-is (no clamping in domain type)
        XCTAssertEqual(packet.sampleRaw, -0.5)
        XCTAssertEqual(packet.sampleSmth, -1.0)
    }
    
    func testValuesAboveOneAllowed() {
        // Document that values > 1.0 are allowed (for peaks/transients)
        let packet = WLEDAudioSyncPacket(
            sampleRaw: 1.5,
            sampleSmth: 2.0
        )
        
        XCTAssertEqual(packet.sampleRaw, 1.5)
        XCTAssertEqual(packet.sampleSmth, 2.0)
    }
}
