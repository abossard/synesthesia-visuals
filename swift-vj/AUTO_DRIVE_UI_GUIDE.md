# Auto-Drive Mode UI Integration Guide

This guide explains how to add UI controls for the auto-drive mode that's been implemented in the state management layer.

## Quick Reference

All the logic is implemented. You just need to add UI controls that call these AppState methods:

```swift
// Set auto-drive mode
appState.setAutoDriveMode(.manual)      // User controls everything
appState.setAutoDriveMode(.autoPhase)   // Auto-select within current phase
appState.setAutoDriveMode(.autoFull)    // Fully automatic

// Set current phase (for AutoPhase mode)
appState.setPhase(.disco)     // Starter songs, 90-125 BPM
appState.setPhase(.buildup)   // Bridge songs, 115-140 BPM  
appState.setPhase(.peak)      // High energy, 135-160 BPM
appState.setPhase(.release)   // Breathing room, atmospheric
appState.setPhase(.feature)   // Special/erratic, remixes
appState.setPhase(nil)        // Auto-detect from AI

// Toggle preference memory
appState.setRememberShaderPreferences(true)
```

## Accessing Current State

Read from the store state:

```swift
@EnvironmentObject var appState: AppState

// Current auto-drive mode
let mode = appState.autoDriveMode  // .manual, .autoPhase, or .autoFull

// Current phase (manual or auto-detected)
let currentPhase = appState.currentPhase  // Set by user
let detectedPhase = appState.detectedSongPhase  // Set by AI
let effectivePhase = appState.effectivePhase  // Current phase (manual ?? detected)

// Preference setting
let rememberPrefs = appState.rememberShaderPreferences
```

## Recommended UI Additions

### 1. Master Control View (Main VJ Controls)

Add to `MasterControlView.swift` in the main control section:

```swift
// Auto-Drive Mode Picker
Picker("Drive Mode", selection: Binding(
    get: { appState.autoDriveMode },
    set: { appState.setAutoDriveMode($0) }
)) {
    ForEach(AutoDriveMode.allCases, id: \.self) { mode in
        Text(mode.displayName).tag(mode)
    }
}
.pickerStyle(.segmented)
.help("Auto-drive mode: Manual, Auto-Phase, or Full Auto")

// Phase Selector (only shown if not in Manual mode)
if appState.autoDriveMode != .manual {
    VStack(alignment: .leading, spacing: 4) {
        Text("Phase:")
            .font(.caption)
            .foregroundColor(.secondary)
        
        HStack(spacing: 8) {
            // Auto button (sets phase to nil)
            Button(action: { appState.setPhase(nil) }) {
                Text("Auto")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(appState.currentPhase == nil ? Color.accentColor : Color.secondary.opacity(0.2))
                    .foregroundColor(appState.currentPhase == nil ? .white : .primary)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            // Phase buttons
            ForEach(Phase.allCases, id: \.self) { phase in
                Button(action: { appState.setPhase(phase) }) {
                    Text(phase.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appState.currentPhase == phase ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(appState.currentPhase == phase ? .white : .primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(phase.description)
            }
        }
        
        // Show detected phase if different from manual
        if let detected = appState.detectedSongPhase, detected != appState.currentPhase {
            Text("AI suggests: \(detected.displayName)")
                .font(.caption2)
                .foregroundColor(.orange)
        }
    }
}

// Status indicator
HStack {
    Circle()
        .fill(appState.autoDriveMode == .manual ? Color.gray : Color.green)
        .frame(width: 8, height: 8)
    
    Text(appState.autoDriveMode.displayName)
        .font(.caption)
        .foregroundColor(.secondary)
}
```

### 2. Settings View (Advanced Configuration)

Add to `SettingsView.swift` in a new "Auto-Drive" tab:

```swift
Form {
    Section("Auto-Drive Mode") {
        Picker("Mode", selection: Binding(
            get: { appState.autoDriveMode },
            set: { appState.setAutoDriveMode($0) }
        )) {
            ForEach(AutoDriveMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading) {
                    Text(mode.displayName)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(mode)
            }
        }
        
        Toggle("Remember manual shader selections", isOn: Binding(
            get: { appState.rememberShaderPreferences },
            set: { appState.setRememberShaderPreferences($0) }
        ))
        .help("When enabled, manual shader selections are saved per song")
        
        if appState.rememberShaderPreferences {
            Button("View Shader Preferences...") {
                // TODO: Show sheet with ShaderPreferenceStore contents
            }
        }
    }
    
    Section("Phase Configuration") {
        Text("Phases help organize your set. Each phase suggests different shader types:")
            .font(.caption)
            .foregroundColor(.secondary)
        
        ForEach(Phase.allCases, id: \.self) { phase in
            VStack(alignment: .leading, spacing: 4) {
                Text(phase.displayName)
                    .font(.headline)
                Text(phase.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
```

### 3. LLM Backend Configuration

Add to `SettingsView.swift` in the "AI" tab:

```swift
Section("LLM Backend") {
    Picker("Backend", selection: $llmBackendSelection) {
        Text("Auto (LM Studio → OpenAI)").tag("auto")
        Text("LM Studio Only").tag("lmstudio")
        Text("OpenAI Only").tag("openai")
        Text("None (Basic Analysis)").tag("none")
    }
    .onChange(of: llmBackendSelection) { newValue in
        Task {
            await appState.settings.setLLMBackend(newValue)
            await appState.aiModule?.llmClient.setBackendPreference(newValue)
        }
    }
    
    if llmBackendSelection == "openai" || llmBackendSelection == "auto" {
        SecureField("OpenAI API Key", text: $openAIKey)
            .textContentType(.password)
            .onChange(of: openAIKey) { newValue in
                Task {
                    await appState.settings.setOpenAIKey(newValue)
                    await appState.aiModule?.llmClient.setOpenAIKey(newValue)
                }
            }
        
        Text("Stored securely in app settings")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

@State private var llmBackendSelection: String = "auto"
@State private var openAIKey: String = ""
```

### 4. Shader Browser Enhancements

Add to `ShaderBrowserView.swift` to show phase tags:

```swift
// In shader card/row, add phase badges
if let phases = shader.phases {
    HStack(spacing: 4) {
        ForEach(Array(phases), id: \.self) { phase in
            Text(phase.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .foregroundColor(.accentColor)
                .cornerRadius(3)
        }
    }
}
```

### 5. Status Bar/Header

Add auto-drive status to the main window header:

```swift
HStack {
    // Existing controls...
    
    Spacer()
    
    // Auto-drive status indicator
    HStack(spacing: 8) {
        Circle()
            .fill(appState.autoDriveMode == .manual ? Color.gray : Color.green)
            .frame(width: 10, height: 10)
        
        VStack(alignment: .trailing, spacing: 2) {
            Text(appState.autoDriveMode.displayName)
                .font(.caption)
                .fontWeight(.medium)
            
            if let phase = appState.effectivePhase {
                Text(phase.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding(8)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(6)
}
```

## State Observation

The UI will automatically update when state changes because `AppState` publishes these values:

```swift
@Published public private(set) var currentPhase: Phase?
@Published public private(set) var detectedSongPhase: Phase?
// Note: autoDriveMode and rememberShaderPreferences need to be synced from store
```

Make sure your views use `@EnvironmentObject var appState: AppState` to observe changes.

## Testing the UI

1. Launch the app
2. Switch to AutoPhase mode
3. Select a phase (e.g., "Peak")
4. Load a track and verify shader auto-selects from peak-compatible shaders
5. Manually select a different shader
6. Play the same track again and verify your manual selection is remembered
7. Switch to AutoFull mode
8. Load a track and verify phase is auto-detected and shader matches both energy/mood and phase

## Keyboard Shortcuts (Optional)

Add these to make DJing easier:

```swift
.keyboardShortcut("1", modifiers: [.command, .shift])  // Manual mode
.keyboardShortcut("2", modifiers: [.command, .shift])  // AutoPhase mode  
.keyboardShortcut("3", modifiers: [.command, .shift])  // AutoFull mode

.keyboardShortcut("d", modifiers: .command)  // Disco phase
.keyboardShortcut("b", modifiers: .command)  // Buildup phase
.keyboardShortcut("p", modifiers: .command)  // Peak phase
.keyboardShortcut("r", modifiers: .command)  // Release phase
.keyboardShortcut("f", modifiers: .command)  // Feature phase
```

## API Reference

### AutoDriveMode

```swift
public enum AutoDriveMode: String, Sendable, Equatable, Codable, CaseIterable {
    case manual      // Full manual control
    case autoPhase   // Auto-select within current phase
    case autoFull    // Fully automatic (phase + shader)
    
    var displayName: String
    var description: String
}
```

### Phase

```swift
public enum Phase: String, Sendable, Codable, CaseIterable, Hashable {
    case disco      // 90-125 BPM, starter songs
    case buildup    // 115-140 BPM, building energy
    case peak       // 135-160 BPM, high energy
    case release    // Atmospheric, breathing room
    case feature    // Special/erratic, remixes
    
    var displayName: String
    var description: String
}
```

### AppState Methods

```swift
// Auto-drive mode
func setAutoDriveMode(_ mode: AutoDriveMode)

// Phase selection
func setPhase(_ phase: Phase?)  // nil = auto-detect

// Preferences
func setRememberShaderPreferences(_ remember: Bool)
```

## How It Works Internally

When you call these methods, here's what happens:

1. **setAutoDriveMode()**: 
   - Dispatches `RenderAction.setAutoDriveMode` to store
   - Updates state and persists to UserDefaults
   - If switching to auto mode, triggers `autoSelectShader` for current track

2. **setPhase()**:
   - Updates `RenderSubState.currentPhase`
   - Persists to UserDefaults
   - In AutoPhase/AutoFull modes, affects shader selection

3. **Track Change Flow**:
   ```
   New Track → Pipeline → AI Analysis → Detect Phase
   ↓
   Pipeline Complete → Check Mode
   ↓
   Manual: Use pipeline suggestion (if any)
   AutoPhase: Auto-select from current phase
   AutoFull: Use detected phase, auto-select
   ```

4. **Shader Selection Logic**:
   - Check `ShaderPreferenceStore` for saved preference
   - If found, use it (bypass auto-selection)
   - If not found:
     - Get candidates matching energy/valence
     - Filter by phase (if in AutoPhase/AutoFull)
     - Apply usage penalty for variety
     - Select best match

## Debug/Testing

To see what's happening:

1. Enable OSC debug to see shader load messages
2. Check logs for `[AutoDrive]` messages
3. View shader preferences file: `~/Library/Application Support/SwiftVJ/shader_preferences.json`

The logs will show:
- `[AutoDrive] Using saved preference: ShaderName`
- `[AutoDrive] Auto-selected: ShaderName (E:0.7 V:0.3 Phase:Peak)`
- `[AutoDrive] No matching shader found`
