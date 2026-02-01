## Plan: LedFX OSC→REST Generator & Paths View

TL;DR: Add a LedFX-driven routing-config generator and a supported-paths catalog in the LedFX UI. Use your running LedFX at http://127.0.0.1:8888 for live probing and validation. Generation will fail if playlists are unavailable, per your decision. The generator will export YAML via Save As… and optionally load it into the bridge for immediate testing.

**Steps**
1. Probe live LedFX endpoints at http://127.0.0.1:8888 to confirm playlists and effects catalog availability; record exact endpoint shapes.
2. Extend `LedFXClient` in swift-vj/Sources/SwiftVJCore/Adapters/LedFXClient.swift and add models in swift-vj/Sources/SwiftVJCore/Domain/LedFXTypes.swift for playlists/effects list, or surface a hard failure if playlists are missing.
3. Add a pure generator that maps LedFX data to `BridgeConfig` in swift-vj/Sources/OscRestBridge/Domain/BridgeConfig.swift, respecting `OSCRouteParser` rules in swift-vj/Sources/OscRestBridge/Domain/OSCRouteParser.swift.
4. Add YAML export support near swift-vj/Sources/OscRestBridge/Domain/ConfigLoader.swift and wire Save As… in swift-vj/Sources/SwiftVJApp/LedFXConfigView.swift.
5. Add Supported OSC Paths view in swift-vj/Sources/SwiftVJApp/LedFXConfigView.swift, grouped by route type and derived from the generated/loaded config.
6. Offer “Load this config” using swift-vj/Sources/OscRestBridge/OscRestBridgeService.swift after export for immediate validation.

**Verification**
- Live API checks against http://127.0.0.1:8888 to confirm playlists/effects endpoints and data.
- Generate config → Save As… → Load config; verify supported paths list populates.
- Send sample OSC routes and confirm REST calls succeed.
- Run Swift unit tests for any new pure generator logic.

**Decisions**
- Base URL for live tests: http://127.0.0.1:8888
- Playlists are required; generation fails if not available.
