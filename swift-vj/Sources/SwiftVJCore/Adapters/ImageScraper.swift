// ImageScraper - Fetch and cache song-related images
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Image Result

/// Result of an image fetch operation
public struct ImageResult: Sendable {
    public let folder: URL
    public let albumArt: Bool
    public let artistPhotos: Int
    public let totalImages: Int
    public let source: String
    public let cached: Bool
    
    public init(
        folder: URL,
        albumArt: Bool = false,
        artistPhotos: Int = 0,
        totalImages: Int = 0,
        source: String = "",
        cached: Bool = false
    ) {
        self.folder = folder
        self.albumArt = albumArt
        self.artistPhotos = artistPhotos
        self.totalImages = totalImages
        self.source = source
        self.cached = cached
    }
}

// MARK: - ImageScraper

/// Deep module for fetching and caching song-related images
///
/// Simple interface:
/// - `fetchImages(for:metadata:)` - Fetch images for a track
/// - `imagesExist(for:)` - Check if images are cached
/// - `getFolder(for:)` - Get cache folder path
///
/// Sources (fetches from ALL, ~16-18 images total):
/// - Cover Art Archive - album covers (~3 images)
/// - Pexels - thematic imagery (5 images)
/// - Pixabay - thematic CC0 imagery (5 images)
/// - Unsplash - thematic imagery (5 images, attribution required)
///
/// All images cached in ~/Library/Application Support/SwiftVJ/song_images/
public actor ImageScraper {
    
    // MARK: - Constants
    
    private let cacheDir: URL
    private let userAgent = "SwiftVJ/1.0 (https://github.com/synesthesia-visuals)"
    
    // API endpoints
    private let musicbrainzAPI = "https://musicbrainz.org/ws/2"
    private let coverArtAPI = "https://coverartarchive.org"
    private let unsplashAPI = "https://api.unsplash.com"
    private let pexelsAPI = "https://api.pexels.com/v1"
    private let pixabayAPI = "https://pixabay.com/api"
    
    // API keys from environment
    private let unsplashKey: String?
    private let pexelsKey: String?
    private let pixabayKey: String?
    
    // Rate limiting
    private var lastMusicBrainzRequest = Date.distantPast
    private var lastUnsplashRequest = Date.distantPast
    private var lastPexelsRequest = Date.distantPast
    private var lastPixabayRequest = Date.distantPast
    
    // MARK: - Init
    
    public init(cacheDir: URL? = nil) {
        // Use Application Support for cache
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDir = cacheDir ?? appSupport.appendingPathComponent("SwiftVJ/song_images")
        
        // Load API keys from environment
        self.unsplashKey = ProcessInfo.processInfo.environment["UNSPLASH_ACCESS_KEY"]
        self.pexelsKey = ProcessInfo.processInfo.environment["PEXELS_API_KEY"]
        self.pixabayKey = ProcessInfo.processInfo.environment["PIXABAY_API_KEY"]
        
        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Fetch and cache images for a track from ALL sources
    ///
    /// - Parameters:
    ///   - track: Track to fetch images for
    ///   - metadata: Optional metadata with themes, keywords, mood
    /// - Returns: ImageResult or nil if no images found
    public func fetchImages(for track: Track, metadata: [String: Any]? = nil) async -> ImageResult? {
        let folder = getFolder(for: track)
        
        // Check cache first
        if imagesExistSync(at: folder) {
            let count = countImages(in: folder)
            print("[ImageScraper] Cache hit: \(track.artist) - \(track.title) (\(count) files)")
            return ImageResult(
                folder: folder,
                albumArt: hasAlbumArt(in: folder),
                artistPhotos: countArtistPhotos(in: folder),
                totalImages: count,
                source: "cache",
                cached: true
            )
        }
        
        // Create folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        var result = ImageResult(folder: folder)
        var sources: [String] = []
        
        // 1. Cover Art Archive (no auth required)
        do {
            let coverCount = try await fetchFromCoverArtArchive(track: track, folder: folder)
            if coverCount > 0 {
                result = ImageResult(
                    folder: folder,
                    albumArt: true,
                    artistPhotos: result.artistPhotos,
                    totalImages: result.totalImages + coverCount,
                    source: result.source,
                    cached: false
                )
                sources.append("coverart")
                print("[ImageScraper] Cover Art Archive: \(coverCount) images")
            }
        } catch {
            print("[ImageScraper] Cover Art Archive failed: \(error)")
        }
        
        // Build search query from metadata
        let query = buildSearchQuery(from: metadata)
        
        // 2. Pexels
        if let query = query, pexelsKey != nil {
            do {
                let count = try await fetchFromPexels(query: query, folder: folder)
                if count > 0 {
                    result = ImageResult(
                        folder: folder,
                        albumArt: result.albumArt,
                        artistPhotos: result.artistPhotos,
                        totalImages: result.totalImages + count,
                        source: result.source,
                        cached: false
                    )
                    sources.append("pexels")
                    print("[ImageScraper] Pexels: \(count) images")
                }
            } catch {
                print("[ImageScraper] Pexels failed: \(error)")
            }
        }
        
        // 3. Pixabay
        if let query = query, pixabayKey != nil {
            do {
                let count = try await fetchFromPixabay(query: query, folder: folder)
                if count > 0 {
                    result = ImageResult(
                        folder: folder,
                        albumArt: result.albumArt,
                        artistPhotos: result.artistPhotos,
                        totalImages: result.totalImages + count,
                        source: result.source,
                        cached: false
                    )
                    sources.append("pixabay")
                    print("[ImageScraper] Pixabay: \(count) images")
                }
            } catch {
                print("[ImageScraper] Pixabay failed: \(error)")
            }
        }
        
        // 4. Unsplash
        if let query = query, unsplashKey != nil {
            do {
                let count = try await fetchFromUnsplash(query: query, folder: folder)
                if count > 0 {
                    result = ImageResult(
                        folder: folder,
                        albumArt: result.albumArt,
                        artistPhotos: result.artistPhotos,
                        totalImages: result.totalImages + count,
                        source: result.source,
                        cached: false
                    )
                    sources.append("unsplash")
                    print("[ImageScraper] Unsplash: \(count) images")
                }
            } catch {
                print("[ImageScraper] Unsplash failed: \(error)")
            }
        }
        
        // Update source
        let finalResult = ImageResult(
            folder: folder,
            albumArt: result.albumArt,
            artistPhotos: result.artistPhotos,
            totalImages: result.totalImages,
            source: sources.joined(separator: "+"),
            cached: false
        )
        
        if finalResult.totalImages > 0 {
            // Save metadata
            saveSourcesMetadata(folder: folder, track: track, result: finalResult)
            return finalResult
        }
        
        return nil
    }
    
    /// Check if images are cached for a track
    public func imagesExist(for track: Track) -> Bool {
        let folder = getFolder(for: track)
        return imagesExistSync(at: folder)
    }
    
    /// Get cache folder path for a track
    public func getFolder(for track: Track) -> URL {
        let safe = sanitizeCacheFilename(artist: track.artist, title: track.title)
        return cacheDir.appendingPathComponent(safe)
    }
    
    /// Get count of cached songs
    public func getCachedCount() -> Int {
        guard FileManager.default.fileExists(atPath: cacheDir.path) else { return 0 }
        
        let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        
        return contents?.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }.count ?? 0
    }
    
    // MARK: - Private - Cover Art Archive
    
    private func fetchFromCoverArtArchive(track: Track, folder: URL) async throws -> Int {
        await rateLimitMusicBrainz()
        
        // Search MusicBrainz for release
        var urlComponents = URLComponents(string: "\(musicbrainzAPI)/recording")!
        let query = "artist:\"\(track.artist)\" AND recording:\"\(track.title)\""
        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return 0
        }
        
        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = json["recordings"] as? [[String: Any]] else {
            return 0
        }
        
        // Try to get cover art from first recording with releases
        for recording in recordings.prefix(3) {
            guard let releases = recording["releases"] as? [[String: Any]] else { continue }
            
            for release in releases.prefix(2) {
                guard let mbid = release["id"] as? String else { continue }
                
                let count = try await downloadCoverArt(mbid: mbid, folder: folder)
                if count > 0 {
                    return count
                }
                
                await rateLimitMusicBrainz()
            }
        }
        
        return 0
    }
    
    private func downloadCoverArt(mbid: String, folder: URL) async throws -> Int {
        // Try front cover first
        let frontURL = URL(string: "\(coverArtAPI)/release/\(mbid)/front-500")!
        
        var request = URLRequest(url: frontURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let ext = httpResponse.mimeType?.contains("png") == true ? "png" : "jpg"
                let filePath = folder.appendingPathComponent("album_cover.\(ext)")
                try data.write(to: filePath)
                return 1
            }
        } catch {
            // Try listing all art
        }
        
        // Try listing all available art
        let listURL = URL(string: "\(coverArtAPI)/release/\(mbid)")!
        request = URLRequest(url: listURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (listData, listResponse) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = listResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return 0
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let images = json["images"] as? [[String: Any]] else {
            return 0
        }
        
        var count = 0
        
        for (i, img) in images.prefix(3).enumerated() {
            guard let thumbnails = img["thumbnails"] as? [String: String],
                  let imgURLString = thumbnails["500"] ?? (img["image"] as? String),
                  let imgURL = URL(string: imgURLString) else {
                continue
            }
            
            let imgType = (img["front"] as? Bool == true) ? "front" :
                          ((img["back"] as? Bool == true) ? "back" : "other")
            
            do {
                var imgRequest = URLRequest(url: imgURL)
                imgRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                
                let (imgData, _) = try await URLSession.shared.data(for: imgRequest)
                
                let filename = "album_\(imgType)_\(i).jpg"
                let filePath = folder.appendingPathComponent(filename)
                try imgData.write(to: filePath)
                count += 1
            } catch {
                continue
            }
        }
        
        return count
    }
    
    // MARK: - Private - Pexels
    
    private func fetchFromPexels(query: String, folder: URL) async throws -> Int {
        guard let apiKey = pexelsKey else { return 0 }
        
        await rateLimitPexels()
        
        var urlComponents = URLComponents(string: "\(pexelsAPI)/search")!
        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "orientation", value: "landscape")
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return 0
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photos = json["photos"] as? [[String: Any]] else {
            return 0
        }
        
        var count = 0
        
        for (i, photo) in photos.prefix(5).enumerated() {
            guard let src = photo["src"] as? [String: String],
                  let imgURLString = src["large"],
                  let imgURL = URL(string: imgURLString) else {
                continue
            }
            
            do {
                let (imgData, _) = try await URLSession.shared.data(from: imgURL)
                
                let filename = "thematic_pexels_\(i).jpg"
                let filePath = folder.appendingPathComponent(filename)
                try imgData.write(to: filePath)
                count += 1
            } catch {
                continue
            }
        }
        
        return count
    }
    
    // MARK: - Private - Pixabay
    
    private func fetchFromPixabay(query: String, folder: URL) async throws -> Int {
        guard let apiKey = pixabayKey else { return 0 }
        
        await rateLimitPixabay()
        
        var urlComponents = URLComponents(string: pixabayAPI)!
        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "orientation", value: "horizontal"),
            URLQueryItem(name: "image_type", value: "photo"),
            URLQueryItem(name: "safesearch", value: "true")
        ]
        
        let (data, response) = try await URLSession.shared.data(from: urlComponents.url!)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return 0
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]] else {
            return 0
        }
        
        var count = 0
        
        for (i, hit) in hits.prefix(5).enumerated() {
            guard let imgURLString = hit["largeImageURL"] as? String,
                  let imgURL = URL(string: imgURLString) else {
                continue
            }
            
            do {
                let (imgData, _) = try await URLSession.shared.data(from: imgURL)
                
                let filename = "thematic_pixabay_\(i).jpg"
                let filePath = folder.appendingPathComponent(filename)
                try imgData.write(to: filePath)
                count += 1
            } catch {
                continue
            }
        }
        
        return count
    }
    
    // MARK: - Private - Unsplash
    
    private func fetchFromUnsplash(query: String, folder: URL) async throws -> Int {
        guard let apiKey = unsplashKey else { return 0 }
        
        await rateLimitUnsplash()
        
        var urlComponents = URLComponents(string: "\(unsplashAPI)/search/photos")!
        urlComponents.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "orientation", value: "landscape")
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Client-ID \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return 0
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return 0
        }
        
        var count = 0
        var attributions: [[String: String]] = []
        
        for (i, photo) in results.prefix(5).enumerated() {
            guard let urls = photo["urls"] as? [String: String],
                  let imgURLString = urls["regular"],
                  let imgURL = URL(string: imgURLString) else {
                continue
            }
            
            do {
                let (imgData, _) = try await URLSession.shared.data(from: imgURL)
                
                let filename = "thematic_unsplash_\(i).jpg"
                let filePath = folder.appendingPathComponent(filename)
                try imgData.write(to: filePath)
                count += 1
                
                // Track attribution
                if let user = photo["user"] as? [String: Any] {
                    attributions.append([
                        "filename": filename,
                        "photographer": user["name"] as? String ?? "Unknown",
                        "source": "unsplash"
                    ])
                }
                
                // Trigger download tracking (Unsplash requirement)
                if let links = photo["links"] as? [String: String],
                   let downloadLocation = links["download_location"],
                   let downloadURL = URL(string: downloadLocation) {
                    var downloadRequest = URLRequest(url: downloadURL)
                    downloadRequest.setValue("Client-ID \(apiKey)", forHTTPHeaderField: "Authorization")
                    _ = try? await URLSession.shared.data(for: downloadRequest)
                }
            } catch {
                continue
            }
        }
        
        // Save attribution
        if !attributions.isEmpty {
            saveAttribution(folder: folder, attributions: attributions, query: query)
        }
        
        return count
    }
    
    // MARK: - Private - Utilities
    
    private func buildSearchQuery(from metadata: [String: Any]?) -> String? {
        guard let metadata = metadata else { return nil }
        
        var terms: [String] = []
        
        // Priority: themes > mood > keywords
        if let themes = metadata["themes"] as? [String] {
            terms.append(contentsOf: themes.prefix(3))
        }
        
        if let mood = metadata["mood"] as? String {
            terms.append(mood)
        }
        
        if let keywords = metadata["keywords"] as? [String], terms.count < 3 {
            for kw in keywords.prefix(5) {
                if !terms.map({ $0.lowercased() }).contains(kw.lowercased()) {
                    terms.append(kw)
                    if terms.count >= 4 { break }
                }
            }
        }
        
        return terms.isEmpty ? nil : terms.prefix(3).joined(separator: " ")
    }
    
    private func imagesExistSync(at folder: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        
        let jpgs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "jpg" } ?? []
        let pngs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "png" } ?? []
        
        return !jpgs.isEmpty || !pngs.isEmpty
    }
    
    private func countImages(in folder: URL) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return 0
        }
        return contents.filter { $0.pathExtension == "jpg" || $0.pathExtension == "png" }.count
    }
    
    private func hasAlbumArt(in folder: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return false
        }
        return contents.contains { $0.lastPathComponent.hasPrefix("album_") }
    }
    
    private func countArtistPhotos(in folder: URL) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return 0
        }
        return contents.filter { $0.lastPathComponent.hasPrefix("artist_") }.count
    }
    
    private func saveSourcesMetadata(folder: URL, track: Track, result: ImageResult) {
        let metadata: [String: Any] = [
            "artist": track.artist,
            "title": track.title,
            "album": track.album,
            "fetched_at": Date().timeIntervalSince1970,
            "source": result.source,
            "album_art": result.albumArt,
            "artist_photos": result.artistPhotos,
            "total_images": result.totalImages
        ]
        
        let metadataFile = folder.appendingPathComponent("sources.json")
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) {
            try? data.write(to: metadataFile)
        }
    }
    
    private func saveAttribution(folder: URL, attributions: [[String: String]], query: String) {
        let data: [String: Any] = [
            "sources": ["unsplash"],
            "query": query,
            "fetched_at": Date().timeIntervalSince1970,
            "photos": attributions,
            "license": "Unsplash License (https://unsplash.com/license)",
            "attribution_required": true
        ]
        
        let attrFile = folder.appendingPathComponent("attribution.json")
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]) {
            try? jsonData.write(to: attrFile)
        }
    }
    
    // Rate limiting
    private func rateLimitMusicBrainz() async {
        let elapsed = Date().timeIntervalSince(lastMusicBrainzRequest)
        if elapsed < 1.0 {
            try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
        }
        lastMusicBrainzRequest = Date()
    }
    
    private func rateLimitPexels() async {
        let elapsed = Date().timeIntervalSince(lastPexelsRequest)
        if elapsed < 1.0 {
            try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
        }
        lastPexelsRequest = Date()
    }
    
    private func rateLimitPixabay() async {
        let elapsed = Date().timeIntervalSince(lastPixabayRequest)
        if elapsed < 0.7 {
            try? await Task.sleep(nanoseconds: UInt64((0.7 - elapsed) * 1_000_000_000))
        }
        lastPixabayRequest = Date()
    }
    
    private func rateLimitUnsplash() async {
        let elapsed = Date().timeIntervalSince(lastUnsplashRequest)
        if elapsed < 3.0 {
            try? await Task.sleep(nanoseconds: UInt64((3.0 - elapsed) * 1_000_000_000))
        }
        lastUnsplashRequest = Date()
    }
}
