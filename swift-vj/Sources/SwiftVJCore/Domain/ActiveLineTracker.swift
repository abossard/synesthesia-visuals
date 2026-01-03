// ActiveLineTracker - Position-driven OSC for active lyrics line
// Following Grokking Simplicity: calculations (pure functions) + actions (OSC side effects)

import Foundation
import OSCKit

/// Protocol for dependency injection of OSC sending
public protocol OSCSending {
    func send(_ address: String, values: [any OSCValue]) throws
}

/// Extension to make OSCHub conform to OSCSending
extension OSCHub: OSCSending {
    public func send(_ address: String, values: [any OSCValue]) throws {
        try sendToProcessing(address, values: values)
    }
}

/// Tracks active lyric line based on playback position and sends OSC updates
///
/// Matches Python textler_engine._send_active_line() behavior:
/// - /textler/line/active [index]
/// - /textler/refrain/active [index, text] (when line is refrain)
/// - /textler/keywords/active [index, keywords] (when line has keywords)
///
/// Usage:
/// 1. Call setLines() when lyrics load
/// 2. Call updatePosition() on each playback position update
/// 3. Tracker dedupes and sends OSC only on line changes
public class ActiveLineTracker {
    
    // MARK: - State
    
    private var lines: [LyricLine] = []
    private var refrainLines: [LyricLine] = []
    private var currentActiveIndex: Int = -1
    private let sender: OSCSending
    
    // MARK: - Init
    
    public init(sender: OSCSending) {
        self.sender = sender
    }
    
    // MARK: - Public API
    
    /// Set the current lyrics lines
    /// Call this when a new track's lyrics are loaded
    public func setLines(_ newLines: [LyricLine]) {
        lines = newLines
        refrainLines = newLines.filter { $0.isRefrain }
        currentActiveIndex = -1
    }
    
    /// Update the playback position and send OSC if active line changed
    /// Call this on each playback position update
    public func updatePosition(_ position: Double) {
        let newIndex = getActiveLineIndex(lines, position: position)
        
        // Only send if line changed
        guard newIndex != currentActiveIndex else { return }
        
        currentActiveIndex = newIndex
        
        // If no active line (before first line or after last), don't send
        guard newIndex >= 0 && newIndex < lines.count else { return }
        
        let line = lines[newIndex]
        
        // Send active line index
        // /textler/line/active [index]
        sendOSC("/textler/line/active", values: [Int32(newIndex)])
        
        // If this is a refrain line, send refrain active too
        // /textler/refrain/active [refrain_index, text]
        if line.isRefrain {
            let refrainIndex = refrainLines.firstIndex { $0.text == line.text } ?? 0
            sendOSC("/textler/refrain/active", values: [Int32(refrainIndex), line.text])
        }
        
        // If this line has keywords, send keywords active
        // /textler/keywords/active [index, keywords]
        if !line.keywords.isEmpty {
            sendOSC("/textler/keywords/active", values: [Int32(newIndex), line.keywords])
        }
    }
    
    /// Reset state (e.g., when track changes)
    public func reset() {
        lines = []
        refrainLines = []
        currentActiveIndex = -1
    }
    
    /// Current active line index (-1 if none)
    public var activeIndex: Int {
        currentActiveIndex
    }
    
    // MARK: - Private
    
    private func sendOSC(_ address: String, values: [any OSCValue]) {
        do {
            try sender.send(address, values: values)
        } catch {
            // Log but don't crash on OSC errors
            print("[ActiveLineTracker] OSC send failed: \(error)")
        }
    }
}
