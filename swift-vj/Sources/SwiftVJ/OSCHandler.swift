import Foundation

/// Handles OSC communication from python-vj
/// Protocol matches python-vj/adapters.py OSC messages
class OSCHandler {
    private let server: OSCServer
    private weak var engine: MetalRenderEngine?
    
    init(port: Int, engine: MetalRenderEngine) {
        self.engine = engine
        self.server = OSCServer(port: port)
        
        setupHandlers()
        
        do {
            try server.start()
            NSLog("OSC server started on port \(port)")
        } catch {
            NSLog("ERROR: Failed to start OSC server: \(error)")
        }
    }
    
    private func setupHandlers() {
        // Karaoke track info: /karaoke/track [active, source, artist, title, album, duration, has_lyrics]
        server.setHandler("/karaoke/track") { [weak self] message in
            let args = message.arguments
            guard args.count >= 7 else {
                NSLog("ERROR: Invalid /karaoke/track message")
                return
            }
            
            let active = (args[0] as? Int32 ?? 0) == 1
            let artist = args[2] as? String ?? ""
            let title = args[3] as? String ?? ""
            
            NSLog("Track: \(artist) - \(title) (active: \(active))")
            
            // Update song info channel
            if active {
                let songInfo = "\(artist)\n\(title)"
                self?.engine?.setText(channel: "songinfo", text: songInfo)
            }
        }
        
        // Karaoke position: /karaoke/pos [position, playing]
        server.setHandler("/karaoke/pos") { [weak self] message in
            let args = message.arguments
            guard args.count >= 2 else { return }
            // Position updates are frequent, handled internally
        }
        
        // Lyrics reset: /karaoke/lyrics/reset []
        server.setHandler("/karaoke/lyrics/reset") { [weak self] _ in
            self?.engine?.setText(channel: "full", text: "")
        }
        
        // Lyrics line: /karaoke/lyrics/line [index, time_sec, text]
        server.setHandler("/karaoke/lyrics/line") { [weak self] message in
            let args = message.arguments
            guard args.count >= 3 else { return }
            // Store lyrics lines for display (requires full state management)
        }
        
        // Active line: /karaoke/line/active [index]
        server.setHandler("/karaoke/line/active") { [weak self] message in
            let args = message.arguments
            guard args.count >= 1 else { return }
            // Highlight active line
        }
        
        // Refrain reset: /karaoke/refrain/reset []
        server.setHandler("/karaoke/refrain/reset") { [weak self] _ in
            self?.engine?.setText(channel: "refrain", text: "")
        }
        
        // Refrain line: /karaoke/refrain/line [index, time_sec, text]
        server.setHandler("/karaoke/refrain/line") { [weak self] message in
            // Store refrain lines
        }
        
        // Refrain active: /karaoke/refrain/active [index, text]
        server.setHandler("/karaoke/refrain/active") { [weak self] message in
            let args = message.arguments
            guard args.count >= 2 else { return }
            
            if let text = args[1] as? String {
                NSLog("Refrain: \(text)")
                self?.engine?.setText(channel: "refrain", text: text)
            }
        }
        
        // Shader load: /shader/load [name, energy, valence]
        server.setHandler("/shader/load") { [weak self] message in
            let args = message.arguments
            guard args.count >= 3 else {
                NSLog("ERROR: Invalid /shader/load message")
                return
            }
            
            let name = args[0] as? String ?? ""
            let energy = args[1] as? Float ?? 0.5
            let valence = args[2] as? Float ?? 0.5
            
            NSLog("Loading shader: \(name) (energy: \(energy), valence: \(valence))")
            
            // TODO: Load shader file from shaders directory
            // For now, keep current shader
        }
        
        // Audio analysis (from Synesthesia via python-vj)
        // /audio/levels [sub_bass, bass, low_mid, mid, high_mid, presence, air, rms]
        server.setHandler("/audio/levels") { [weak self] message in
            let args = message.arguments
            guard args.count >= 8 else { return }
            
            let bass = args[1] as? Float ?? 0.0
            let mid = args[3] as? Float ?? 0.0
            let high = args[5] as? Float ?? 0.0
            
            self?.engine?.updateAudioUniforms(bass: bass, mid: mid, high: high, bpm: 120.0)
        }
        
        NSLog("OSC handlers configured")
    }
    
    func stop() {
        server.stop()
        NSLog("OSC server stopped")
    }
}
