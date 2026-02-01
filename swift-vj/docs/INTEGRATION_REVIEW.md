# SwiftVJ Integration Review (LedFX, OSC Rest Bridge, Launchpad)

## Scope
This review covers the recent LedFX integration, OSC Rest Bridge, and Launchpad support updates, with focus on:
- Always-on usability and failure modes
- Main-thread impact
- Module reuse (especially OSCHub)

## Findings & Recommendations

### 1) LedFX enable flow should stay on even when LedFX is offline
**Observation:** The LedFX toggle previously disabled itself if `LedFXModule.start()` failed, which blocks users from keeping the integration on when the server is offline or momentarily unreachable. Since LedFX actions only occur on explicit UI actions or specific OSC messages, it is safe (and expected) for the integration to stay enabled even if the server is currently unreachable. This also aligns with the “always-on” expectation.  
**Update applied:** The toggle now remains enabled; a warning is shown when the server is unreachable. Users can retry with “Test Connection” or by refreshing later.  
**Code:** `LedFXConfigView.startLedFX()` no longer forces `ledfxEnabled = false` on startup failure.【F:Sources/SwiftVJApp/LedFXConfigView.swift†L282-L292】

**Recommendation (follow-up):** Consider distinguishing between “Enabled” and “Connected” state in the UI (e.g., a status pill) so it’s obvious the module is on but offline. This would reduce confusion about whether the toggle “worked.”

### 2) OSC Rest Bridge handling should avoid main-thread work
**Observation:** The OSC Rest Bridge subscription for `/ledfx/*` messages used a `@MainActor` task to call `OscRestBridgeService.handleOSCMessage`, which can do non-trivial work (parsing, request planning). This can introduce UI jank or contention with rendering if many OSC events arrive.  
**Update applied:** The subscription now pulls the `oscRestBridge` reference on the main actor but processes the message off the main thread.  
**Code:** `startOSCHub()` now captures the bridge via `MainActor.run` and calls `handleOSCMessage` outside of it.【F:Sources/SwiftVJApp/SwiftVJApp.swift†L675-L682】

### 3) OSC Rest Bridge config must still be loaded manually
**Observation:** The Osc Rest Bridge service is instantiated at app startup, but no configuration is loaded automatically. This means the bridge will remain idle until a YAML config is loaded (via the OSC Bridge UI or via the LedFX config generator).  
**Code:** `createDefaultBridgeService()` is called during app setup, but no call to `loadConfig` occurs in app startup paths.【F:Sources/SwiftVJApp/SwiftVJApp.swift†L563-L567】【F:Sources/OscRestBridge/OscRestBridgeService.swift†L56-L85】

**Recommendation:** Consider providing a one-click “Load bundled LedFX config” button that loads `config-ledfx.yaml` from the OscRestBridge bundle. This would reduce “missing file / config not loaded” confusion and lower setup friction for users who just want the default mapping.

### 4) OSCHub reuse looks correct and consistent
**Observation:** OSC Rest Bridge and Launchpad are both wired through the existing `OSCHub` subscription system rather than introducing a parallel OSC listener. This is consistent with the design to centralize OSC transport and helps avoid multiple ports and redundant listeners.  
**Code:** `startOSCHub()` subscribes to `/ledfx/*` and to Launchpad OSC routes using the same `oscHub` instance.【F:Sources/SwiftVJApp/SwiftVJApp.swift†L595-L682】

### 5) Launchpad YAML config load failures are non-fatal but silent to users
**Observation:** Launchpad YAML loading is attempted during `EffectExecutor` initialization, but failures are only printed to the console. If the resource is missing, users may not understand why custom layouts/labels aren’t applied.  
**Code:** `LaunchpadConfigLoader.loadBundled()` is called in `EffectExecutor.init()`, with failures printed to stdout.【F:Sources/SwiftVJCore/Launchpad/EffectExecutor.swift†L74-L90】

**Recommendation:** Consider surfacing a UI warning or log entry (e.g., in the app’s log pane) when the YAML config fails to load, similar to other system messages.

## Stability & Robustness Summary
- LedFX module and client are actor-isolated and use clean error propagation; they look robust for network usage.  
- The OSC Rest Bridge is cleanly isolated as a module and routes through OSCHub; the architecture is good and avoids redundant listeners.  
- The Launchpad YAML integration is defensively handled (non-fatal on missing config), but user-facing feedback could be improved.

## Main-Thread Impact Summary
- OSC Rest Bridge now avoids using the main actor for message handling (reduced UI contention).  
- LedFX config generation uses a detached task with explicit main-thread updates, which is appropriate for heavy REST calls.
