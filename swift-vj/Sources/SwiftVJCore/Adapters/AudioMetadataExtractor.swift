// AudioMetadataExtractor.swift - Extract ID3 metadata from audio files
// Uses AVFoundation for reading audio file metadata

import Foundation
import AVFoundation

// MARK: - Audio Metadata Extraction

/// Pure functions for extracting metadata from audio files
public enum AudioMetadata {
    /// Supported audio file extensions
    public static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "alac"
    ]

    /// Check if a file URL is a supported audio file
    public static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Extract artist and title from an audio file
    /// Returns nil if metadata cannot be read or is missing
    public static func extractMetadata(from url: URL) -> (artist: String, title: String)? {
        let asset = AVURLAsset(url: url)

        var artist: String?
        var title: String?

        let metadata = asset.commonMetadata
        for item in metadata {
            guard let key = item.commonKey else { continue }

            switch key {
            case .commonKeyArtist:
                artist = item.stringValue
            case .commonKeyTitle:
                title = item.stringValue
            default:
                break
            }
        }

        // Only return if we have both artist and title
          guard let extractedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines),
              let extractedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !extractedArtist.isEmpty,
              !extractedTitle.isEmpty else {
            return nil
        }

        return (artist: extractedArtist, title: extractedTitle)
    }

    /// Scan a directory recursively for audio files
    /// Returns array of file URLs
    public static func findAudioFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var audioFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            if isSupportedAudioFile(fileURL) {
                audioFiles.append(fileURL)
            }
        }

        return audioFiles
    }
}
