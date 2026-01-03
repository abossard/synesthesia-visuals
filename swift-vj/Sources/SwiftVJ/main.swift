// SwiftVJ CLI - Command-line entry point
// Each module supports standalone execution for testing

import ArgumentParser
import SwiftVJCore
import Foundation

@main
struct SwiftVJCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-vj",
        abstract: "Swift VJ Control Application",
        version: swiftVJVersion,
        subcommands: [
            LyricsCommand.self,
            LaunchpadTestCommand.self,
            // PipelineCommand.self,  // TODO: Implement
            // PlaybackCommand.self,  // TODO: Implement
            // ShadersCommand.self,   // TODO: Implement
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Lyrics Command

struct LyricsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lyrics",
        abstract: "Fetch and parse lyrics for a song"
    )

    @Option(name: [.short, .long], help: "Artist name")
    var artist: String

    @Option(name: [.short, .long], help: "Song title")
    var title: String

    @Option(name: .long, help: "Album name (optional)")
    var album: String = ""

    @Flag(name: .long, help: "Show detailed line-by-line output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Parse local LRC file instead of fetching")
    var local: Bool = false

    func run() async throws {
        print("SwiftVJ Lyrics Module")
        print(String(repeating: "=", count: 60))
        print("Artist: \(artist)")
        print("Title: \(title)")
        if !album.isEmpty {
            print("Album: \(album)")
        }
        print()

        if local {
            // Demo: parse sample LRC
            let sampleLRC = """
            [00:05.12]Is this the real life
            [00:08.34]Is this just fantasy
            [00:11.56]Caught in a landslide
            [00:14.78]No escape from reality
            [00:18.00]Open your eyes
            [00:21.22]Look up to the skies and see
            """

            let lines = parseLRC(sampleLRC)
            let analyzed = analyzeLyrics(lines)

            print("Parsed \(analyzed.count) lines")
            print()

            for (index, line) in analyzed.enumerated() {
                let refrain = line.isRefrain ? " [REFRAIN]" : ""
                let keywords = line.keywords.isEmpty ? "" : " (\(line.keywords))"
                if verbose {
                    print(String(format: "%3d | %6.2f | %@%@%@",
                                index, line.timeSec, line.text, refrain, keywords))
                } else {
                    print("[\(String(format: "%02d:%05.2f", Int(line.timeSec) / 60, line.timeSec.truncatingRemainder(dividingBy: 60)))] \(line.text)\(refrain)")
                }
            }

            print()
            print("Refrains: \(analyzed.filter { $0.isRefrain }.count) lines")
        } else {
            print("TODO: Implement LRCLIB fetch")
            print("Use --local to demo LRC parsing with sample data")
        }
    }
}

// MARK: - Launchpad Test Command

struct LaunchpadTestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchpad-test",
        abstract: "Interactive hardware tests for Launchpad Mini MK3"
    )
    
    @Argument(help: "Test number (1-8) or 'all'")
    var test: String?
    
    func run() throws {
        print()
        print("🎹 LAUNCHPAD MINI MK3 - INTERACTIVE TESTS")
        print(String(repeating: "=", count: 50))
        print()
        print("Make sure Launchpad is connected and in PROGRAMMER mode:")
        print("  → Hold Session → Press orange button → Release")
        print()
        
        let testNumber: Int?
        if let t = test {
            if t.lowercased() == "all" {
                testNumber = nil  // Will run menu which has 'all' option
            } else if let num = Int(t), num >= 1, num <= 8 {
                testNumber = num
            } else {
                print("Invalid test: \(t)")
                print("Use 1-8 or 'all'")
                return
            }
        } else {
            testNumber = nil
        }
        
        runLaunchpadInteractiveTests(testNumber: testNumber)
    }
}
