import SwiftVJCore

/// Test fixtures for LedFX mapping configurations.
enum LedFXFixtures {
    struct MappingScenario {
        let label: String
        let mappings: [LedFXMapping]
        let buttonName: String
        let expectedTarget: String?
        let expectedIsScene: Bool
    }

    static let scenarios: [MappingScenario] = [
        MappingScenario(
            label: "blackout triggers 'off' scene",
            mappings: [
                LedFXMapping(os2lButtonName: "blackout", playlistName: "off", isScene: true),
                LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
            ],
            buttonName: "blackout",
            expectedTarget: "off",
            expectedIsScene: true
        ),
        MappingScenario(
            label: "wildcard captures button name as playlist",
            mappings: [
                LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
            ],
            buttonName: "drop",
            expectedTarget: "drop",
            expectedIsScene: false
        ),
        MappingScenario(
            label: "exact match takes priority over wildcard",
            mappings: [
                LedFXMapping(os2lButtonName: "strobe", playlistName: "party-strobe"),
                LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
            ],
            buttonName: "strobe",
            expectedTarget: "party-strobe",
            expectedIsScene: false
        ),
    ]
}
