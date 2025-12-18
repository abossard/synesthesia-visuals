import Foundation
import CoreGraphics

enum ROIKey: String, CaseIterable, Identifiable {
    case d1Artist, d1Title, d1Elapsed, d1Fader
    case d2Artist, d2Title, d2Elapsed, d2Fader
    var id: String { rawValue }
    var label: String {
        switch self {
        case .d1Artist: return "Deck 1 · Artist"
        case .d1Title: return "Deck 1 · Title"
        case .d1Elapsed: return "Deck 1 · Elapsed time"
        case .d1Fader: return "Deck 1 · Fader"
        case .d2Artist: return "Deck 2 · Artist"
        case .d2Title: return "Deck 2 · Title"
        case .d2Elapsed: return "Deck 2 · Elapsed time"
        case .d2Fader: return "Deck 2 · Fader"
        }
    }
}

struct CalibrationModel: Codable {
    // Normalized rects: origin TOP-LEFT in 0..1 (matches UI)
    var rois: [ROIKey: CGRect] = [:]

    // thresholds for fader gray detection
    var grayLo: Int = 90
    var grayHi: Int = 140
    var eqTol: Int = 15
    var minHits: Int = 8
    
    // Language correction toggles per field (helps with non-English artist names)
    var d1ArtistLangCorrection: Bool = false
    var d1TitleLangCorrection: Bool = false
    var d2ArtistLangCorrection: Bool = false
    var d2TitleLangCorrection: Bool = false
    
    func usesLanguageCorrection(for key: ROIKey) -> Bool {
        switch key {
        case .d1Artist: return d1ArtistLangCorrection
        case .d1Title: return d1TitleLangCorrection
        case .d2Artist: return d2ArtistLangCorrection
        case .d2Title: return d2TitleLangCorrection
        default: return false
        }
    }

    static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("VDJStatus").appendingPathComponent("vdj_calibration.json")
    }()

    mutating func set(_ key: ROIKey, rect: CGRect) { rois[key] = rect.standardized }
    func get(_ key: ROIKey) -> CGRect? { rois[key] }

    func isComplete() -> Bool {
        ROIKey.allCases.allSatisfy { rois[$0] != nil }
    }

    func saveToDisk() {
        do {
            let dir = Self.saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.saveURL, options: .atomic)
            print("[Calibration] Saved to \(Self.saveURL.path)")
        } catch {
            print("[Calibration] ERROR saving: \(error.localizedDescription)")
        }
    }

    static func loadFromDisk() -> CalibrationModel? {
        do {
            let data = try Data(contentsOf: saveURL)
            let model = try JSONDecoder().decode(CalibrationModel.self, from: data)
            print("[Calibration] Loaded \(model.rois.count) ROIs from \(saveURL.path)")
            return model
        } catch {
            print("[Calibration] No saved calibration found: \(error.localizedDescription)")
            return nil
        }
    }
}

// Custom Codable for ROIKey dictionary
extension CalibrationModel {
    enum CodingKeys: String, CodingKey {
        case rois, grayLo, grayHi, eqTol, minHits
        case d1ArtistLangCorrection, d1TitleLangCorrection
        case d2ArtistLangCorrection, d2TitleLangCorrection
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let roisDict = try container.decode([String: CGRect].self, forKey: .rois)
        self.rois = roisDict.compactMapKeys { ROIKey(rawValue: $0) }
        self.grayLo = try container.decode(Int.self, forKey: .grayLo)
        self.grayHi = try container.decode(Int.self, forKey: .grayHi)
        self.eqTol = try container.decode(Int.self, forKey: .eqTol)
        self.minHits = try container.decode(Int.self, forKey: .minHits)
        // Language correction settings (with defaults for backward compat)
        self.d1ArtistLangCorrection = try container.decodeIfPresent(Bool.self, forKey: .d1ArtistLangCorrection) ?? false
        self.d1TitleLangCorrection = try container.decodeIfPresent(Bool.self, forKey: .d1TitleLangCorrection) ?? false
        self.d2ArtistLangCorrection = try container.decodeIfPresent(Bool.self, forKey: .d2ArtistLangCorrection) ?? false
        self.d2TitleLangCorrection = try container.decodeIfPresent(Bool.self, forKey: .d2TitleLangCorrection) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let roisDict = Dictionary(uniqueKeysWithValues: rois.map { ($0.key.rawValue, $0.value) })
        try container.encode(roisDict, forKey: .rois)
        try container.encode(grayLo, forKey: .grayLo)
        try container.encode(grayHi, forKey: .grayHi)
        try container.encode(eqTol, forKey: .eqTol)
        try container.encode(minHits, forKey: .minHits)
        try container.encode(d1ArtistLangCorrection, forKey: .d1ArtistLangCorrection)
        try container.encode(d1TitleLangCorrection, forKey: .d1TitleLangCorrection)
        try container.encode(d2ArtistLangCorrection, forKey: .d2ArtistLangCorrection)
        try container.encode(d2TitleLangCorrection, forKey: .d2TitleLangCorrection)
    }
}

extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        try reduce(into: [:]) { result, pair in
            if let key = try transform(pair.key) {
                result[key] = pair.value
            }
        }
    }
}
