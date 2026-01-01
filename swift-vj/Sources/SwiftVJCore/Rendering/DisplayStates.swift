// Display States - Immutable state for rendering tiles
// Following Grokking Simplicity: pure data types

import Foundation

// MARK: - Lyrics Display State

/// State for lyrics tile rendering
public struct LyricsDisplayState: Sendable, Equatable {
    public let lines: [LyricLine]
    public let activeIndex: Int
    public let textOpacity: Float  // 0-255

    public init(
        lines: [LyricLine] = [],
        activeIndex: Int = -1,
        textOpacity: Float = 255
    ) {
        self.lines = lines
        self.activeIndex = activeIndex
        self.textOpacity = textOpacity
    }

    /// Previous lyric line (if any)
    public var prevLine: String? {
        guard activeIndex > 0, activeIndex - 1 < lines.count else { return nil }
        return lines[activeIndex - 1].text
    }

    /// Current lyric line (if any)
    public var currentLine: String? {
        guard activeIndex >= 0, activeIndex < lines.count else { return nil }
        return lines[activeIndex].text
    }

    /// Next lyric line (if any)
    public var nextLine: String? {
        guard activeIndex + 1 < lines.count else { return nil }
        return lines[activeIndex + 1].text
    }

    /// Create new state with updated active index
    public func withActiveIndex(_ index: Int) -> LyricsDisplayState {
        LyricsDisplayState(lines: lines, activeIndex: index, textOpacity: textOpacity)
    }

    /// Create new state with updated lines
    public func withLines(_ newLines: [LyricLine]) -> LyricsDisplayState {
        LyricsDisplayState(lines: newLines, activeIndex: -1, textOpacity: textOpacity)
    }

    /// Create new state with updated opacity
    public func withOpacity(_ opacity: Float) -> LyricsDisplayState {
        LyricsDisplayState(lines: lines, activeIndex: activeIndex, textOpacity: opacity)
    }
}

// MARK: - Refrain Display State

/// State for refrain/chorus tile rendering
public struct RefrainDisplayState: Sendable, Equatable {
    public let text: String
    public let opacity: Float  // 0-255
    public let active: Bool

    public init(
        text: String = "",
        opacity: Float = 0,
        active: Bool = false
    ) {
        self.text = text
        self.opacity = opacity
        self.active = active
    }

    /// Create new state with text and activate
    public func withText(_ newText: String) -> RefrainDisplayState {
        RefrainDisplayState(text: newText, opacity: 255, active: true)
    }

    /// Create new state with updated opacity
    public func withOpacity(_ newOpacity: Float) -> RefrainDisplayState {
        RefrainDisplayState(text: text, opacity: newOpacity, active: active)
    }

    /// Create inactive state
    public static var inactive: RefrainDisplayState {
        RefrainDisplayState()
    }
}

// MARK: - Song Info Display State

/// State for song info tile rendering (with fade envelope)
public struct SongInfoDisplayState: Sendable, Equatable {
    public let artist: String
    public let title: String
    public let album: String
    public let opacity: Float       // 0-255
    public let displayTime: Float   // Seconds since shown
    public let active: Bool

    // Fade envelope timing (seconds)
    public static let fadeInDuration: Float = 0.5
    public static let holdDuration: Float = 5.0
    public static let fadeOutDuration: Float = 1.0

    public init(
        artist: String = "",
        title: String = "",
        album: String = "",
        opacity: Float = 0,
        displayTime: Float = 0,
        active: Bool = false
    ) {
        self.artist = artist
        self.title = title
        self.album = album
        self.opacity = opacity
        self.displayTime = displayTime
        self.active = active
    }

    /// Total duration of fade envelope
    public static var totalDuration: Float {
        fadeInDuration + holdDuration + fadeOutDuration
    }

    /// Calculate opacity from display time. Pure function.
    public static func opacityForTime(_ time: Float) -> Float {
        if time < fadeInDuration {
            // Fade in
            return (time / fadeInDuration) * 255
        } else if time < fadeInDuration + holdDuration {
            // Hold at full opacity
            return 255
        } else if time < totalDuration {
            // Fade out
            let fadeProgress = (time - fadeInDuration - holdDuration) / fadeOutDuration
            return (1.0 - fadeProgress) * 255
        } else {
            return 0
        }
    }

    /// Create state for new track
    public static func forTrack(artist: String, title: String, album: String = "") -> SongInfoDisplayState {
        SongInfoDisplayState(
            artist: artist,
            title: title,
            album: album,
            opacity: 0,
            displayTime: 0,
            active: true
        )
    }

    /// Update state with delta time
    public func advanced(by deltaTime: Float) -> SongInfoDisplayState {
        let newTime = displayTime + deltaTime
        let newOpacity = Self.opacityForTime(newTime)
        let newActive = newTime < Self.totalDuration

        return SongInfoDisplayState(
            artist: artist,
            title: title,
            album: album,
            opacity: newOpacity,
            displayTime: newTime,
            active: newActive
        )
    }
}

// MARK: - Image Display State

/// State for image tile rendering
public struct ImageDisplayState: Sendable, Equatable {
    public let currentImagePath: String?
    public let nextImagePath: String?
    public let crossfadeProgress: Float  // 0.0 - 1.0
    public let isFading: Bool
    public let coverMode: Bool  // true = cover (crop), false = contain (letterbox)

    // Folder mode
    public let folderImages: [String]
    public let folderIndex: Int
    public let beatsPerChange: Int  // 0 = manual, 1 = every beat, 4 = every 4 beats

    public init(
        currentImagePath: String? = nil,
        nextImagePath: String? = nil,
        crossfadeProgress: Float = 1.0,
        isFading: Bool = false,
        coverMode: Bool = false,
        folderImages: [String] = [],
        folderIndex: Int = 0,
        beatsPerChange: Int = 4
    ) {
        self.currentImagePath = currentImagePath
        self.nextImagePath = nextImagePath
        self.crossfadeProgress = crossfadeProgress
        self.isFading = isFading
        self.coverMode = coverMode
        self.folderImages = folderImages
        self.folderIndex = folderIndex
        self.beatsPerChange = beatsPerChange
    }

    /// Whether in folder mode
    public var isFolderMode: Bool {
        !folderImages.isEmpty
    }

    /// Create state for single image
    public static func forImage(path: String) -> ImageDisplayState {
        ImageDisplayState(
            currentImagePath: nil,
            nextImagePath: path,
            crossfadeProgress: 0,
            isFading: true
        )
    }
}

// MARK: - Shader Display State

/// State for shader tile rendering
public struct ShaderDisplayState: Sendable, Equatable {
    public let name: String
    public let path: String
    public let rating: ShaderRating
    public let isLoaded: Bool
    public let error: String?

    public init(
        name: String = "",
        path: String = "",
        rating: ShaderRating = .normal,
        isLoaded: Bool = false,
        error: String? = nil
    ) {
        self.name = name
        self.path = path
        self.rating = rating
        self.isLoaded = isLoaded
        self.error = error
    }

    /// Create state for loaded shader
    public static func loaded(name: String, path: String, rating: ShaderRating) -> ShaderDisplayState {
        ShaderDisplayState(name: name, path: path, rating: rating, isLoaded: true)
    }

    /// Create state for failed shader
    public static func failed(name: String, error: String) -> ShaderDisplayState {
        ShaderDisplayState(name: name, isLoaded: false, error: error)
    }
}

// MARK: - Pure Functions for Image Rendering

/// Calculate aspect-ratio preserving dimensions. Pure function.
/// Returns (x, y, width, height) for centered drawing.
public func calcAspectRatioDimensions(
    imageWidth: Float,
    imageHeight: Float,
    bufferWidth: Float,
    bufferHeight: Float,
    cover: Bool
) -> (x: Float, y: Float, width: Float, height: Float) {
    let imageAspect = imageWidth / imageHeight
    let bufferAspect = bufferWidth / bufferHeight

    let drawWidth: Float
    let drawHeight: Float

    if cover {
        // Cover mode: fill container, may crop
        if imageAspect > bufferAspect {
            // Image wider - fit height, crop sides
            drawHeight = bufferHeight
            drawWidth = bufferHeight * imageAspect
        } else {
            // Image taller - fit width, crop top/bottom
            drawWidth = bufferWidth
            drawHeight = bufferWidth / imageAspect
        }
    } else {
        // Contain mode: show all, may have letterboxing
        if imageAspect > bufferAspect {
            // Image wider - fit width
            drawWidth = bufferWidth
            drawHeight = bufferWidth / imageAspect
        } else {
            // Image taller - fit height
            drawHeight = bufferHeight
            drawWidth = bufferHeight * imageAspect
        }
    }

    // Center in buffer
    let x = (bufferWidth - drawWidth) / 2
    let y = (bufferHeight - drawHeight) / 2

    return (x: x, y: y, width: drawWidth, height: drawHeight)
}

/// Quadratic ease-in-out for smooth transitions. Pure function.
public func easeInOutQuad(_ t: Float) -> Float {
    if t < 0.5 {
        return 2 * t * t
    } else {
        return 1 - pow(-2 * t + 2, 2) / 2
    }
}
