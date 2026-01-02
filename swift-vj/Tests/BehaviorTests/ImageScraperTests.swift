// ImageScraperTests - Tests for image fetching behavior

import XCTest
@testable import SwiftVJCore

final class ImageScraperTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitWithDefaults() async throws {
        let scraper = ImageScraper()
        XCTAssertNotNil(scraper)
    }
    
    func testInitWithCustomCacheDir() async throws {
        let customDir = URL(fileURLWithPath: "/tmp/test_images_\(UUID().uuidString)")
        let scraper = ImageScraper(cacheDir: customDir)
        XCTAssertNotNil(scraper)
    }
    
    // MARK: - Folder Path Tests
    
    func testGetFolderForTrack() async throws {
        let scraper = ImageScraper()
        let track = Track(artist: "The Beatles", title: "Hey Jude")
        
        let folder = await scraper.getFolder(for: track)
        
        XCTAssertTrue(folder.path.contains("beatles") || folder.path.contains("Beatles"))
    }
    
    // MARK: - Cache Check Tests
    
    func testImagesExistReturnsFalseForNewTrack() async throws {
        let tempDir = URL(fileURLWithPath: "/tmp/image_test_\(UUID().uuidString)")
        let scraper = ImageScraper(cacheDir: tempDir)
        let track = Track(artist: "NonExistent", title: "Track123")
        
        let exists = await scraper.imagesExist(for: track)
        
        XCTAssertFalse(exists)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Cache Count Tests
    
    func testGetCachedCountReturnsZeroForEmptyDir() async throws {
        let tempDir = URL(fileURLWithPath: "/tmp/image_test_\(UUID().uuidString)")
        let scraper = ImageScraper(cacheDir: tempDir)
        
        let count = await scraper.getCachedCount()
        
        XCTAssertEqual(count, 0)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
