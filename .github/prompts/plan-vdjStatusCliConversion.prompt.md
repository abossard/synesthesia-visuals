# Plan: Convert VDJStatus Xcode App to SwiftPM CLI Tool

Convert the existing SwiftUI-based VDJStatus app into a headless terminal tool using Swift Package Manager, preserving ScreenCaptureKit capture, OCR detection, and OSC output while adding a togglable AppKit debug window via keyboard input.

## Steps

1. **Create SwiftPM project structure** with `Package.swift`, `Sources/vdj-cli/main.swift`, and migrate reusable components (`CaptureManager`, `VisionOCR`, `Detector`, `DeckStateMachine`, `CalibrationModel`, `OSC`) — strip Combine publishers and `@MainActor` annotations.

2. **Implement CLI entry point** in `main.swift` with argument parsing (Swift Argument Parser), raw terminal mode for single-key input (`d` toggle), and an async main loop that dispatches capture → detect → log every 2–3 seconds.

3. **Add AppKit debug window support** by lazily initializing `NSApplication.shared` on first `d` press, creating an `NSWindow` with a placeholder view, and toggling visibility on subsequent presses — run the AppKit event loop on the main thread via `DispatchQueue.main.async`.

4. **Bundle Info.plist** via SwiftPM resources (macOS 13.0+) containing `NSScreenCaptureUsageDescription` key; explain that during development permission attaches to Terminal.app, and for distribution recommend a minimal `.app` wrapper.

5. **Provide terminal build/run commands** (`swift build -c release`, `swift run vdj-cli --osc-host 127.0.0.1 --osc-port 9000`) and document common failure modes (permission denied, window not found, capture timeout) with actionable log messages.

## Further Considerations

1. **Argument parser choice?** — Recommend Swift Argument Parser (official Apple library, declarative, auto help generation) over manual parsing. Add as dependency in `Package.swift`.

2. **Debug window content?** — Initial implementation shows a `"VDJStatus Debug"` label; future iterations can embed live frame preview or state dump. Confirm blank label is acceptable.

3. **Distribution format?** — For distribution outside development, wrap the CLI binary inside a minimal `.app` bundle (Info.plist + executable) so macOS TCC grants screen recording permission to the app rather than Terminal.app. Document this step or defer?
