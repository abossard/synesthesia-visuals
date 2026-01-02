// SpotifyMonitor - Query Spotify playback via AppleScript
// Following Grokking Simplicity: this is an action (side effects)

import Foundation

/// Playback information from Spotify
public struct SpotifyPlayback: Sendable, Equatable {
    public let artist: String
    public let title: String
    public let album: String
    public let durationMs: Int
    public let positionMs: Int
    public let isPlaying: Bool
    
    public init(
        artist: String,
        title: String,
        album: String,
        durationMs: Int,
        positionMs: Int,
        isPlaying: Bool
    ) {
        self.artist = artist
        self.title = title
        self.album = album
        self.durationMs = durationMs
        self.positionMs = positionMs
        self.isPlaying = isPlaying
    }
    
    /// Track key for change detection
    public var trackKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }
}

/// Error types for Spotify monitoring
public enum SpotifyMonitorError: Error, Equatable {
    case spotifyNotRunning
    case scriptError(String)
    case parseError(String)
    case noTrackPlaying
}

/// Monitor Spotify playback via AppleScript (macOS only)
public final class SpotifyMonitor: @unchecked Sendable {
    
    /// AppleScript to query Spotify
    private static let script = """
    tell application "System Events"
        if not (exists process "Spotify") then
            return "NOT_RUNNING"
        end if
    end tell
    
    tell application "Spotify"
        if player state is stopped then
            return "STOPPED"
        end if
        
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set trackDuration to duration of current track
        set trackPosition to player position
        set isPlaying to player state is playing
        
        return trackArtist & "|||" & trackName & "|||" & trackAlbum & "|||" & (trackDuration as string) & "|||" & (trackPosition as string) & "|||" & (isPlaying as string)
    end tell
    """
    
    private let health: ServiceHealth
    
    public init() {
        self.health = ServiceHealth(name: "Spotify")
    }
    
    /// Query current Spotify playback
    public func getPlayback() async throws -> SpotifyPlayback {
        let result = try await runAppleScript(Self.script)
        
        if result == "NOT_RUNNING" {
            await health.markUnavailable(error: "Spotify not running")
            throw SpotifyMonitorError.spotifyNotRunning
        }
        
        if result == "STOPPED" {
            await health.markUnavailable(error: "No track playing")
            throw SpotifyMonitorError.noTrackPlaying
        }
        
        // Parse the result: artist|||title|||album|||duration|||position|||isPlaying
        let parts = result.components(separatedBy: "|||")
        guard parts.count == 6 else {
            await health.markUnavailable(error: "Parse error: unexpected format")
            throw SpotifyMonitorError.parseError("Unexpected format: \(result)")
        }
        
        let artist = parts[0]
        let title = parts[1]
        let album = parts[2]
        
        // Duration is in milliseconds from Spotify
        let durationMs = Int(Double(parts[3]) ?? 0)
        
        // Position is in seconds from Spotify, convert to ms
        let positionMs = Int((Double(parts[4]) ?? 0) * 1000)
        
        let isPlaying = parts[5].lowercased() == "true"
        
        await health.markAvailable(message: "Connected to Spotify")
        
        return SpotifyPlayback(
            artist: artist,
            title: title,
            album: album,
            durationMs: durationMs,
            positionMs: positionMs,
            isPlaying: isPlaying
        )
    }
    
    /// Check if Spotify is running
    public func isSpotifyRunning() async -> Bool {
        do {
            let result = try await runAppleScript("""
                tell application "System Events"
                    return exists process "Spotify"
                end tell
            """)
            return result.lowercased() == "true"
        } catch {
            return false
        }
    }
    
    /// Get service health status
    public func status() async -> [String: Any] {
        await health.status()
    }
    
    // MARK: - Private
    
    private func runAppleScript(_ source: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: SpotifyMonitorError.scriptError("Failed to create script"))
                    return
                }
                
                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                
                if let error = errorInfo {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(throwing: SpotifyMonitorError.scriptError(message))
                    return
                }
                
                let stringValue = result.stringValue ?? ""
                continuation.resume(returning: stringValue)
            }
        }
    }
}
