// WLEDModule - WLED Sound Reactive integration module
// Following Module protocol pattern
// Transforms Swift-VJ audio data → WLED UDP packets

import Foundation

/// Module for WLED Sound Reactive integration
/// Subscribes to audio data and sends UDP sync packets to WLED controllers
public actor WLEDModule: Module {
    
    // MARK: - Dependencies
    
    private let adapter: WLEDAdapter
    private let oscHub: OSCHub?
    private var config: WLEDConfig
    
    // MARK: - State
    
    public private(set) var isStarted = false
    private var updateTask: Task<Void, Never>?
    private var lastPacket: WLEDAudioSyncPacket = .silent
    private var audioLevels: OSCAudioLevels = OSCAudioLevels()
    
    // FFT smoothing state (16 bands)
    private var smoothedFFT: [Float] = Array(repeating: 0, count: 16)
    
    // Stats
    private var packetsProcessed: Int = 0
    private var controllersActive: Int = 0
    
    // MARK: - Initialization
    
    public init(
        adapter: WLEDAdapter = WLEDAdapter(),
        oscHub: OSCHub? = nil,
        config: WLEDConfig = .default
    ) {
        self.adapter = adapter
        self.oscHub = oscHub
        self.config = config
    }
    
    // MARK: - Module Lifecycle
    
    public func start() async throws {
        guard !isStarted else {
            throw ModuleError.alreadyStarted
        }
        
        // Start adapter
        await adapter.start()
        
        // Subscribe to audio OSC messages if oscHub available
        if let osc = oscHub {
            subscribeToAudio(osc)
        }
        
        // Start update loop
        startUpdateLoop()
        
        isStarted = true
        controllersActive = config.controllers.filter { $0.enabled }.count
        
        print("WLEDModule started with \(controllersActive) active controllers")
    }
    
    public func stop() async {
        guard isStarted else { return }
        
        // Stop update loop
        updateTask?.cancel()
        updateTask = nil
        
        // Stop adapter
        await adapter.stop()
        
        isStarted = false
        print("WLEDModule stopped")
    }
    
    // MARK: - Audio Data Handling
    
    /// Update audio levels from Synesthesia OSC
    /// Called by OSC subscription handler at ~60 Hz
    public func updateAudioLevels(_ levels: OSCAudioLevels) {
        audioLevels = levels
    }
    
    /// Subscribe to Synesthesia audio OSC messages
    private func subscribeToAudio(_ osc: OSCHub) {
        // Subscribe to all Synesthesia audio messages
        osc.subscribe(pattern: "/syn/*") { [weak self] address, values in
            guard let self = self else { return }
            
            // Extract audio data from OSC messages
            // This is a placeholder - actual implementation would parse OSC values
            // and call updateAudioLevels() with extracted data
            
            Task {
                // Example: parse bass level from /syn/level/bass
                if address == "/syn/level/bass", let bass = values.first as? Float {
                    var levels = await self.audioLevels
                    // Update levels (this is simplified - real impl would be more complete)
                    await self.updateAudioLevels(OSCAudioLevels(
                        bass: bass,
                        lowMid: levels.lowMid,
                        mid: levels.mid,
                        highs: levels.highs,
                        level: levels.level,
                        hitsBass: levels.hitsBass,
                        onBeat: levels.onBeat,
                        beatTime: levels.beatTime,
                        bpmTwitcher: levels.bpmTwitcher,
                        bpmSin4: levels.bpmSin4,
                        bpmConfidence: levels.bpmConfidence,
                        energyIntensity: levels.energyIntensity,
                        bassPresence: levels.bassPresence,
                        midPresence: levels.midPresence,
                        highPresence: levels.highPresence
                    ))
                }
            }
        }
    }
    
    // MARK: - Update Loop
    
    /// Start periodic update loop to send packets to WLED controllers
    private func startUpdateLoop() {
        let intervalMs = 1000.0 / Double(config.updateRateHz)
        
        updateTask = Task {
            while !Task.isCancelled {
                // Convert audio data to WLED packet
                let packet = await createPacket()
                
                // Send to all enabled controllers
                if config.enabled {
                    let failed = await adapter.send(packet, to: config.controllers)
                    if !failed.isEmpty {
                        print("Failed to send to controllers: \(failed.joined(separator: ", "))")
                    }
                }
                
                packetsProcessed += 1
                
                // Sleep until next update
                try? await Task.sleep(for: .milliseconds(Int(intervalMs)))
            }
        }
    }
    
    // MARK: - Packet Creation
    
    /// Create WLED audio sync packet from current audio state
    /// Pure calculation - transforms OSCAudioLevels → WLEDAudioSyncPacket
    private func createPacket() -> WLEDAudioSyncPacket {
        // Raw sample: overall level (0-1 range)
        let sampleRaw = audioLevels.level
        
        // Smoothed sample: use slow energy envelope
        let sampleSmth = audioLevels.level * 0.7 + audioLevels.bassPresence * 0.3
        
        // Peak detection: trigger on bass hits
        let samplePeak: UInt8 = audioLevels.hitsBass > 0.5 ? 1 : 0
        
        // Create 16-band FFT spectrum from available frequency bands
        // Map Swift-VJ's 4 bands (bass, lowMid, mid, highs) to WLED's 16 bands
        let fftBands = createFFTBands()
        
        // FFT magnitude: highest band value
        let fftMagnitude = fftBands.max() ?? 0
        
        // FFT major peak: index of highest band (0-15)
        let maxIndex = fftBands.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let fftMajorPeak = Float(maxIndex)
        
        return WLEDAudioSyncPacket(
            sampleRaw: sampleRaw,
            sampleSmth: sampleSmth,
            samplePeak: samplePeak,
            reserved1: 0,
            fftResult: fftBands,
            fftMagnitude: fftMagnitude,
            fftMajorPeak: fftMajorPeak
        )
    }
    
    /// Create 16-band FFT spectrum from 4-band audio levels
    /// Pure function - maps Swift-VJ bands → WLED FFT bands with smoothing
    private func createFFTBands() -> [UInt8] {
        // Map 4 bands to 16 bands with interpolation
        // Bands 0-3: bass
        // Bands 4-7: lowMid
        // Bands 8-11: mid
        // Bands 12-15: highs
        
        var rawBands: [Float] = []
        
        // Bass (bands 0-3)
        for _ in 0..<4 {
            rawBands.append(audioLevels.bass)
        }
        
        // Low-mid (bands 4-7)
        for _ in 0..<4 {
            rawBands.append(audioLevels.lowMid)
        }
        
        // Mid (bands 8-11)
        for _ in 0..<4 {
            rawBands.append(audioLevels.mid)
        }
        
        // Highs (bands 12-15)
        for _ in 0..<4 {
            rawBands.append(audioLevels.highs)
        }
        
        // Apply EMA smoothing
        let smoothing = config.fftSmoothing
        for i in 0..<16 {
            smoothedFFT[i] = smoothedFFT[i] * smoothing + rawBands[i] * (1.0 - smoothing)
        }
        
        // Convert to UInt8 (0-255 range)
        return smoothedFFT.map { value in
            UInt8(max(0, min(255, value * 255)))
        }
    }
    
    // MARK: - Configuration
    
    /// Update module configuration
    public func updateConfig(_ newConfig: WLEDConfig) {
        config = newConfig
        controllersActive = config.controllers.filter { $0.enabled }.count
        
        // Restart update loop with new rate if changed
        if isStarted {
            updateTask?.cancel()
            startUpdateLoop()
        }
    }
    
    /// Get current configuration
    public func getConfig() -> WLEDConfig {
        config
    }
    
    /// Add a new WLED controller
    public func addController(_ controller: WLEDController) {
        var newConfig = config
        var controllers = config.controllers
        controllers.append(controller)
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        controllersActive = config.controllers.filter { $0.enabled }.count
    }
    
    /// Remove a WLED controller by ID
    public func removeController(id: String) {
        var controllers = config.controllers
        controllers.removeAll { $0.id == id }
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        controllersActive = config.controllers.filter { $0.enabled }.count
    }
    
    // MARK: - Status
    
    public func getStatus() -> [String: Any] {
        var status: [String: Any] = [
            "started": isStarted,
            "enabled": config.enabled,
            "controllers": config.controllers.count,
            "controllersActive": controllersActive,
            "updateRateHz": config.updateRateHz,
            "packetsProcessed": packetsProcessed
        ]
        
        // Include adapter stats
        Task {
            let adapterStats = await adapter.stats()
            status["adapter"] = adapterStats
        }
        
        return status
    }
}
