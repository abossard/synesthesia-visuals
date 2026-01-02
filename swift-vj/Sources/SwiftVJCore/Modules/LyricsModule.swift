// LyricsModule - Fetch, parse, and sync lyrics with playback position
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation

/// Lyrics module - fetches and tracks lyrics timing
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle
/// - `loadLyrics(for:)` - fetch and parse lyrics for track
/// - `getActiveLine(at:)` - find current line at position
/// - `onActiveLineChange` - callback when active line changes
///
/// Hides: LRCLIB API, caching, LRC parsing, refrain detection
public actor LyricsModule: Module {
    
    // MARK: - State
    
    public private(set) var isStarted: Bool = false
    private var currentTrack: Track?
    private var currentLines: [LyricLine] = []
    private var currentActiveIndex: Int = -1
    private var hasLyrics: Bool = false
    
    // Adapters
    private let fetcher: LyricsFetcher
    
    // Settings
    private let _timingOffsetMs: Int
    private var timingOffsetSec: Double { Double(_timingOffsetMs) / 1000.0 }
    
    // Callbacks
    private var activeLineCallbacks: [(Int, LyricLine?) -> Void] = []
    
    // MARK: - Init
    
    public init(fetcher: LyricsFetcher, timingOffsetMs: Int = 0) {
        self.fetcher = fetcher
        self._timingOffsetMs = timingOffsetMs
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        isStarted = true
        print("[Lyrics] Started")
    }
    
    public func stop() async {
        isStarted = false
        currentTrack = nil
        currentLines = []
        currentActiveIndex = -1
        print("[Lyrics] Stopped")
    }
    
    public func getStatus() -> [String: Any] {
        [
            "started": isStarted,
            "has_lyrics": hasLyrics,
            "line_count": currentLines.count,
            "active_index": currentActiveIndex,
            "current_track": currentTrack?.key ?? "none"
        ]
    }
    
    // MARK: - Public API
    
    /// Timing offset in milliseconds
    public var timingOffset: Int { _timingOffsetMs }
    
    /// Load lyrics for a track
    /// Returns the parsed lyric lines or empty array if not found
    public func loadLyrics(for track: Track) async -> [LyricLine] {
        currentTrack = track
        currentActiveIndex = -1
        
        do {
            // Fetch LRC text
            guard let lrcText = try await fetcher.fetch(artist: track.artist, title: track.title) else {
                currentLines = []
                hasLyrics = false
                print("[Lyrics] Not found: \(track.artist) - \(track.title)")
                return []
            }
            
            // Parse LRC into lines
            currentLines = parseLRC(lrcText)
            hasLyrics = !currentLines.isEmpty
            
            print("[Lyrics] Loaded \(currentLines.count) lines for: \(track.artist) - \(track.title)")
            return currentLines
            
        } catch {
            currentLines = []
            hasLyrics = false
            print("[Lyrics] Error: \(track.artist) - \(track.title): \(error)")
            return []
        }
    }
    
    /// Get current lyrics lines
    public var lines: [LyricLine] {
        currentLines
    }
    
    /// Check if lyrics are loaded
    public var lyricsLoaded: Bool {
        hasLyrics
    }
    
    /// Get the active line index for a given position (with timing offset applied)
    public func getActiveLineIndex(at position: Double) -> Int {
        let adjustedPosition = position + timingOffsetSec
        return SwiftVJCore.getActiveLineIndex(currentLines, position: adjustedPosition)
    }
    
    /// Get the active line at position
    public func getActiveLine(at position: Double) -> LyricLine? {
        let index = getActiveLineIndex(at: position)
        guard index >= 0 && index < currentLines.count else { return nil }
        return currentLines[index]
    }
    
    /// Update position and fire callbacks if active line changed
    public func updatePosition(_ position: Double) async {
        let newIndex = getActiveLineIndex(at: position)
        
        if newIndex != currentActiveIndex {
            currentActiveIndex = newIndex
            let line = newIndex >= 0 && newIndex < currentLines.count ? currentLines[newIndex] : nil
            
            for callback in activeLineCallbacks {
                callback(newIndex, line)
            }
        }
    }
    
    /// Register callback for active line changes
    public func onActiveLineChange(_ callback: @escaping (Int, LyricLine?) -> Void) {
        activeLineCallbacks.append(callback)
    }
    
    /// Get current active index
    public var activeIndex: Int {
        currentActiveIndex
    }
    
    /// Get refrain lines
    public var refrainLines: [LyricLine] {
        currentLines.filter { $0.isRefrain }
    }
    
    /// Get keywords from all lines
    public var keywords: [String] {
        currentLines.compactMap { $0.keywords }.flatMap { $0.split(separator: " ").map(String.init) }
    }
}
