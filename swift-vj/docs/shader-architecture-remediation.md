# Shader Architecture Remediation Checklist

This checklist tracks the agreed architecture fixes and verification status.

- [x] 1. Single source of truth for shader state (main + mask in Store state)
- [x] 2. Views call actions only (no direct render engine selection mutations)
- [x] 3. Actor boundary for shader file operations
- [x] 4. Remove legacy shader-management paths and enforce isolation
- [x] 5. Deterministic startup ordering for repository load and initial selection

## Verification

- [x] Build compiles after refactor
- [x] Reducer tests pass for render selection (main + mask + navigation)
- [x] Shader file operation tests pass for actor-backed operations
- [x] No direct `renderEngine.shaderSelection.*` calls remain in SwiftUI views

## Test Runs

- `swift test --package-path /Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj --filter RenderReducerTests` (pass)
- `swift test --package-path /Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj --filter StoreTests` (pass)
- `swift test --package-path /Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj --filter ShaderFileOperationsActorTests` (pass)
- `swift test --package-path /Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj --filter Shader` (pass; some repository/file E2E tests skip when external shader fixture paths are unavailable)
- `swift test --package-path /Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj` (pass; suite-wide run with environment-gated skips only)
