// PrefixTrie - Efficient O(n) prefix matching for OSC patterns
// Following Grokking Simplicity: this is a data structure (calculation)

import Foundation

/// Pattern entry stored at trie nodes
public struct PatternEntry<T>: Sendable where T: Sendable {
    public let order: Int
    public let pattern: String
    public let value: T
    
    public init(order: Int, pattern: String, value: T) {
        self.order = order
        self.pattern = pattern
        self.value = value
    }
}

/// Trie node for prefix matching
final class PrefixTrieNode<T>: @unchecked Sendable where T: Sendable {
    var children: [Character: PrefixTrieNode<T>] = [:]
    var entries: [PatternEntry<T>] = []
}

/// Prefix trie for efficient O(path.length) pattern matching
///
/// Use case: OSC pattern subscriptions where patterns are:
/// - "*" or "/" - match all (stored separately)
/// - "/exact/path" - exact match
/// - "/prefix*" - prefix match (stored in trie)
///
/// Performance:
/// - add: O(prefix.length)
/// - match: O(path.length), returns all matching prefixes
public final class PrefixTrie<T>: @unchecked Sendable where T: Sendable {
    
    private let root = PrefixTrieNode<T>()
    private let lock = NSLock()
    
    public init() {}
    
    /// Add a prefix pattern with associated value
    ///
    /// - Parameters:
    ///   - prefix: The prefix string (without trailing *)
    ///   - entry: The pattern entry to store
    public func add(_ prefix: String, entry: PatternEntry<T>) {
        lock.withLock {
            var node = root
            for char in prefix {
                if node.children[char] == nil {
                    node.children[char] = PrefixTrieNode<T>()
                }
                node = node.children[char]!
            }
            node.entries.append(entry)
        }
    }
    
    /// Remove all entries for a prefix
    public func remove(_ prefix: String) {
        lock.withLock {
            var node = root
            for char in prefix {
                guard let next = node.children[char] else { return }
                node = next
            }
            node.entries.removeAll()
        }
    }
    
    /// Find all entries whose prefix matches the given path
    ///
    /// Returns entries in order of prefix length (shortest first).
    /// For path "/audio/level/bass", matches:
    /// - "" (root)
    /// - "/audio"
    /// - "/audio/level"
    /// - "/audio/level/bass"
    ///
    /// - Parameter path: The full path to match
    /// - Returns: Array of matching entries
    public func match(_ path: String) -> [PatternEntry<T>] {
        lock.withLock {
            var matches: [PatternEntry<T>] = []
            var node = root
            
            // Check root entries (empty prefix matches all)
            if !node.entries.isEmpty {
                matches.append(contentsOf: node.entries)
            }
            
            // Walk down the trie following path characters
            for char in path {
                guard let next = node.children[char] else {
                    break
                }
                node = next
                if !node.entries.isEmpty {
                    matches.append(contentsOf: node.entries)
                }
            }
            
            return matches
        }
    }
    
    /// Clear all entries
    public func clear() {
        lock.withLock {
            root.children.removeAll()
            root.entries.removeAll()
        }
    }
    
    /// Number of prefix patterns stored
    public var count: Int {
        lock.withLock {
            countNodes(root)
        }
    }
    
    private func countNodes(_ node: PrefixTrieNode<T>) -> Int {
        var total = node.entries.count
        for child in node.children.values {
            total += countNodes(child)
        }
        return total
    }
}
