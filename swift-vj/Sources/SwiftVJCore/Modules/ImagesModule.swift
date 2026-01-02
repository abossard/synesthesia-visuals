// ImagesModule - Module wrapper for image scraping
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation

/// Images module - provides image fetching and caching
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle
/// - `fetchImages(for:metadata:)` - fetch and cache images
/// - `imagesExist(for:)` - check cache
/// - `getFolder(for:)` - get cache folder path
///
/// Hides: API calls, rate limiting, caching, attribution tracking
public actor ImagesModule: Module {
    
    // MARK: - State
    
    public private(set) var isStarted: Bool = false
    
    private let scraper: ImageScraper
    private var lastFetchedTrack: String?
    private var lastResult: ImageResult?
    
    // MARK: - Init
    
    public init(scraper: ImageScraper = ImageScraper()) {
        self.scraper = scraper
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        isStarted = true
        print("[Images] Started")
    }
    
    public func stop() async {
        isStarted = false
        print("[Images] Stopped")
    }
    
    public func getStatus() -> [String: Any] {
        var status: [String: Any] = [
            "started": isStarted,
            "cached_count": cachedCount
        ]
        
        if let last = lastFetchedTrack {
            status["last_fetched"] = last
        }
        
        if let result = lastResult {
            status["last_image_count"] = result.totalImages
            status["last_source"] = result.source
        }
        
        return status
    }
    
    // MARK: - Public API
    
    /// Fetch and cache images for a track
    ///
    /// Fetches from multiple sources (Cover Art Archive, Pexels, Pixabay, Unsplash).
    /// Skips if images already cached.
    ///
    /// - Parameters:
    ///   - track: Track to fetch images for
    ///   - metadata: Optional metadata with themes, keywords, mood for thematic search
    /// - Returns: ImageResult or nil if no images found
    public func fetchImages(for track: Track, metadata: [String: Any]? = nil) async -> ImageResult? {
        lastFetchedTrack = "\(track.artist) - \(track.title)"
        
        let result = await scraper.fetchImages(for: track, metadata: metadata)
        lastResult = result
        
        if let result = result {
            print("[Images] Fetched \(result.totalImages) images for \(track.title)")
        }
        
        return result
    }
    
    /// Fetch images using visual adjectives from AI analysis
    ///
    /// - Parameters:
    ///   - track: Track to fetch images for
    ///   - visualAdjectives: List of visual adjectives from AI analysis
    ///   - themes: List of themes from AI analysis
    ///   - mood: Mood from AI analysis
    /// - Returns: ImageResult or nil if no images found
    public func fetchImages(
        for track: Track,
        visualAdjectives: [String],
        themes: [String],
        mood: String
    ) async -> ImageResult? {
        let metadata: [String: Any] = [
            "visual_adjectives": visualAdjectives,
            "themes": themes,
            "mood": mood,
            "keywords": visualAdjectives + themes
        ]
        
        return await fetchImages(for: track, metadata: metadata)
    }
    
    /// Check if images are cached for a track
    public func imagesExist(for track: Track) async -> Bool {
        await scraper.imagesExist(for: track)
    }
    
    /// Get cache folder path for a track
    public func getFolder(for track: Track) async -> URL {
        await scraper.getFolder(for: track)
    }
    
    /// Get count of cached songs
    public var cachedCount: Int {
        get async { await scraper.getCachedCount() }
    }
    
    /// Get last fetch result
    public var currentResult: ImageResult? {
        lastResult
    }
}
