// Pure Functions - Calculations with no side effects
// Following Grokking Simplicity: functions that only depend on their inputs

import Foundation

// MARK: - Stop Words

/// Common words to filter out from keyword extraction
public let stopWords: Set<String> = [
    "i", "me", "my", "we", "our", "you", "your", "he", "she", "it", "they",
    "the", "a", "an", "and", "but", "or", "if", "so", "as", "at", "by", "for",
    "in", "of", "on", "to", "up", "is", "am", "are", "was", "be", "been",
    "have", "has", "had", "do", "does", "did", "will", "can", "could", "would",
    "should", "may", "might", "must", "shall", "this", "that", "these", "those",
    "what", "which", "who", "when", "where", "why", "how", "all", "each",
    "yeah", "oh", "ah", "ooh", "uh", "na", "la", "da", "hey", "gonna", "wanna",
    "gotta", "cause", "like", "just", "now", "here", "there", "with", "from",
    "into", "out", "over", "under", "again", "then", "once", "more", "some",
    "no", "not", "only", "own", "same", "too", "very", "got", "get", "let"
]

// MARK: - LRC Parsing

/// Parse LRC format lyrics into LyricLine objects.
/// Pure function - no side effects.
///
/// LRC Format: `[mm:ss.xx]text` or `[mm:ss.xxx]text`
///
/// - Parameter lrcText: Raw LRC text with timestamps
/// - Returns: Array of LyricLine instances sorted by time
public func parseLRC(_ lrcText: String) -> [LyricLine] {
    // Pattern matches [mm:ss.xx] or [mm:ss.xxx] followed by text
    let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$"#
    let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)

    guard let regex = regex else { return [] }

    var lines: [LyricLine] = []

    for line in lrcText.components(separatedBy: .newlines) {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            continue
        }

        guard
            let minutesRange = Range(match.range(at: 1), in: line),
            let secondsRange = Range(match.range(at: 2), in: line),
            let fractionRange = Range(match.range(at: 3), in: line),
            let textRange = Range(match.range(at: 4), in: line)
        else {
            continue
        }

        let minutes = Double(line[minutesRange]) ?? 0
        let seconds = Double(line[secondsRange]) ?? 0
        let fractionStr = String(line[fractionRange])

        // Handle both .xx (centiseconds) and .xxx (milliseconds) formats
        let fraction: Double
        if fractionStr.count == 3 {
            fraction = (Double(fractionStr) ?? 0) / 1000.0
        } else {
            fraction = (Double(fractionStr) ?? 0) / 100.0
        }

        let timeSec = minutes * 60 + seconds + fraction
        let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)

        if !text.isEmpty {
            lines.append(LyricLine(timeSec: timeSec, text: text))
        }
    }

    return lines.sorted { $0.timeSec < $1.timeSec }
}

// MARK: - Keyword Extraction

/// Extract important words from text. Pure function.
///
/// - Parameters:
///   - text: Input text to extract keywords from
///   - maxWords: Maximum number of keywords to return
/// - Returns: Uppercase keywords separated by spaces
public func extractKeywords(_ text: String, maxWords: Int = 3) -> String {
    let words = text.lowercased()
        .components(separatedBy: CharacterSet.letters.inverted)
        .filter { !$0.isEmpty && $0.count > 2 && !stopWords.contains($0) }

    return words.prefix(maxWords)
        .map { $0.uppercased() }
        .joined(separator: " ")
}

// MARK: - Refrain Detection

/// Mark lines that appear multiple times as refrain. Pure function.
///
/// - Parameter lines: Input lyric lines
/// - Returns: New array with refrain flags and keywords set
public func detectRefrains(_ lines: [LyricLine]) -> [LyricLine] {
    guard !lines.isEmpty else { return [] }

    // Normalize and count line occurrences
    let normalize: (String) -> String = { text in
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "")
    }

    var counts: [String: Int] = [:]
    for line in lines {
        let key = normalize(line.text)
        counts[key, default: 0] += 1
    }

    // Lines appearing 2+ times are refrain
    let refrainKeys = Set(counts.filter { $0.value >= 2 }.keys)

    // Create new array with refrain marked and keywords extracted
    return lines.map { line in
        let isRefrain = refrainKeys.contains(normalize(line.text))
        let keywords = extractKeywords(line.text)
        return line.withRefrain(isRefrain).withKeywords(keywords)
    }
}

/// Full lyrics analysis pipeline. Pure function.
public func analyzeLyrics(_ lines: [LyricLine]) -> [LyricLine] {
    detectRefrains(lines)
}

// MARK: - Active Line Detection

/// Find the active line index for current position. Pure function.
///
/// - Parameters:
///   - lines: Lyric lines with timestamps
///   - position: Current playback position in seconds
/// - Returns: Index of active line, or -1 if no active line
public func getActiveLineIndex(_ lines: [LyricLine], position: Double) -> Int {
    var active = -1
    for (index, line) in lines.enumerated() {
        if line.timeSec <= position {
            active = index
        } else {
            break
        }
    }
    return active
}

/// Get refrain lines only. Pure function.
public func getRefrainLines(_ lines: [LyricLine]) -> [LyricLine] {
    lines.filter { $0.isRefrain }
}

// MARK: - Cache Filename

/// Create a safe filename from artist and title for cache purposes.
/// Removes special characters and normalizes whitespace.
public func sanitizeCacheFilename(artist: String, title: String) -> String {
    let combined = "\(artist)_\(title)".lowercased()
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    let safe = combined
        .components(separatedBy: allowed.inverted)
        .joined()
    return safe.components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .joined(separator: "_")
}

// MARK: - Energy/Valence Calculation

/// Calculate energy score from category scores. Pure function.
///
/// - Parameter scores: Category name to score mapping
/// - Returns: Energy value 0.0-1.0
public func calculateEnergy(from scores: [String: Double]) -> Double {
    let highEnergy = ["energetic", "aggressive", "uplifting"]
    let lowEnergy = ["calm", "peaceful", "sad"]

    let highSum = highEnergy.reduce(0.0) { $0 + (scores[$1] ?? 0) }
    let lowSum = lowEnergy.reduce(0.0) { $0 + (scores[$1] ?? 0) }

    guard highSum + lowSum > 0 else { return 0.5 }
    return min(1.0, max(0.0, highSum / (highSum + lowSum + 0.001)))
}

/// Calculate valence (mood brightness) from category scores. Pure function.
///
/// - Parameter scores: Category name to score mapping
/// - Returns: Valence value -1.0 to 1.0
public func calculateValence(from scores: [String: Double]) -> Double {
    let positive = ["happy", "uplifting", "love", "romantic", "peaceful"]
    let negative = ["dark", "sad", "death", "aggressive"]

    let posSum = positive.reduce(0.0) { $0 + (scores[$1] ?? 0) }
    let negSum = negative.reduce(0.0) { $0 + (scores[$1] ?? 0) }

    let total = posSum + negSum
    guard total > 0 else { return 0 }
    return (posSum - negSum) / total
}

// MARK: - Shader Matching

/// Build target feature vector for shader matching. Pure function.
///
/// - Parameters:
///   - energy: Energy level 0.0-1.0
///   - valence: Mood valence -1.0 to 1.0
/// - Returns: Feature vector [energy, valence, warmth, motion, geometric, density]
public func buildShaderTargetVector(energy: Double, valence: Double) -> [Double] {
    [
        energy,
        valence,
        0.5 + (valence * 0.3),  // Warmth correlates with valence
        energy * 0.7,           // Motion correlates with energy
        0.5,                    // Neutral geometric
        energy * 0.5 + 0.25     // Density correlates with energy
    ]
}

/// Calculate distance between two feature vectors. Pure function.
public func featureDistance(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return Double.infinity }
    let sumSquares = zip(a, b).reduce(0.0) { sum, pair in
        let diff = pair.0 - pair.1
        return sum + diff * diff
    }
    return sqrt(sumSquares)
}
