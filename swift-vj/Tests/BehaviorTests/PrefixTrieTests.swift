// PrefixTrieTests - Verify O(n) prefix matching for OSC patterns

import Testing
@testable import SwiftVJCore

struct PrefixTrieTests {
    
    // MARK: - Basic Operations
    
    @Test func test_add_and_match_singlePrefix() {
        let trie = PrefixTrie<String>()
        
        trie.add("/audio", entry: PatternEntry(order: 0, pattern: "/audio*", value: "audio-handler"))
        
        let matches = trie.match("/audio/level/bass")
        
        #expect(matches.count == 1)
        #expect(matches[0].value == "audio-handler")
    }
    
    @Test func test_match_multipleMatchingPrefixes() {
        let trie = PrefixTrie<String>()
        
        trie.add("/audio", entry: PatternEntry(order: 0, pattern: "/audio*", value: "audio"))
        trie.add("/audio/level", entry: PatternEntry(order: 1, pattern: "/audio/level*", value: "level"))
        trie.add("/audio/level/bass", entry: PatternEntry(order: 2, pattern: "/audio/level/bass*", value: "bass"))
        
        let matches = trie.match("/audio/level/bass")
        
        // Should match all three prefixes (shortest to longest)
        #expect(matches.count == 3)
        #expect(matches.map { $0.value } == ["audio", "level", "bass"])
    }
    
    @Test func test_match_noMatchingPrefix() {
        let trie = PrefixTrie<String>()
        
        trie.add("/audio", entry: PatternEntry(order: 0, pattern: "/audio*", value: "audio"))
        
        let matches = trie.match("/video/stream")
        
        #expect(matches.isEmpty)
    }
    
    @Test func test_match_emptyPrefixMatchesAll() {
        let trie = PrefixTrie<String>()
        
        trie.add("", entry: PatternEntry(order: 0, pattern: "*", value: "catch-all"))
        
        let matches1 = trie.match("/audio/level")
        let matches2 = trie.match("/anything/at/all")
        
        #expect(matches1.count == 1)
        #expect(matches2.count == 1)
    }
    
    @Test func test_match_partialPrefixNoMatch() {
        let trie = PrefixTrie<String>()
        
        trie.add("/audio/level", entry: PatternEntry(order: 0, pattern: "/audio/level*", value: "level"))
        
        // "/audio" is shorter than the prefix, shouldn't match
        let matches = trie.match("/audio")
        
        #expect(matches.isEmpty)
    }
    
    // MARK: - Edge Cases
    
    @Test func test_remove_prefix() {
        let trie = PrefixTrie<String>()
        
        trie.add("/audio", entry: PatternEntry(order: 0, pattern: "/audio*", value: "audio"))
        trie.remove("/audio")
        
        let matches = trie.match("/audio/level")
        
        #expect(matches.isEmpty)
    }
    
    @Test func test_clear_removesAll() {
        let trie = PrefixTrie<String>()
        
        trie.add("/audio", entry: PatternEntry(order: 0, pattern: "/audio*", value: "audio"))
        trie.add("/video", entry: PatternEntry(order: 1, pattern: "/video*", value: "video"))
        trie.clear()
        
        #expect(trie.count == 0)
    }
    
    @Test func test_count_tracksEntries() {
        let trie = PrefixTrie<String>()
        
        #expect(trie.count == 0)
        
        trie.add("/audio", entry: PatternEntry(order: 0, pattern: "/audio*", value: "a"))
        trie.add("/video", entry: PatternEntry(order: 1, pattern: "/video*", value: "v"))
        
        #expect(trie.count == 2)
    }
    
    // MARK: - OSC Use Case
    
    @Test func test_oscPatternMatching() {
        let trie = PrefixTrie<Int>()
        
        // Simulate OSC subscriptions
        trie.add("/textler", entry: PatternEntry(order: 0, pattern: "/textler*", value: 1))
        trie.add("/audio", entry: PatternEntry(order: 1, pattern: "/audio*", value: 2))
        trie.add("/audio/level", entry: PatternEntry(order: 2, pattern: "/audio/level*", value: 3))
        
        // Match /textler/track
        let textlerMatches = trie.match("/textler/track")
        #expect(textlerMatches.count == 1)
        #expect(textlerMatches[0].value == 1)
        
        // Match /audio/level/bass (matches both /audio and /audio/level)
        let audioMatches = trie.match("/audio/level/bass")
        #expect(audioMatches.count == 2)
        #expect(audioMatches.map { $0.value } == [2, 3])
        
        // Match /audio/beat/onbeat (matches only /audio)
        let beatMatches = trie.match("/audio/beat/onbeat")
        #expect(beatMatches.count == 1)
        #expect(beatMatches[0].value == 2)
    }
}
