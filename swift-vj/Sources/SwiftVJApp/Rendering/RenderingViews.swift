// RenderingViews.swift - SwiftUI views for VJ rendering preview
// Phase 6: Visual rendering system views

import SwiftUI
import Metal
import MetalKit

// MARK: - Render Preview View

/// Main view for rendering output preview
struct RenderPreviewView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var renderEngine: RenderEngine
    @State private var selectedTile: String = "shader"

    var body: some View {
        VStack(spacing: 0) {
            // Tile selector
            HStack(spacing: 12) {
                ForEach(["shader", "lyrics", "refrain", "songInfo", "image"], id: \.self) { tile in
                    Button {
                        selectedTile = tile
                    } label: {
                        Text(tile.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTile == tile ? .blue : .gray)
                }

                Spacer()

                // FPS indicator
                Text("\(Int(renderEngine.fps)) FPS")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Tile preview
            TilePreviewView(tileName: selectedTile, renderEngine: renderEngine)
                .aspectRatio(16/9, contentMode: .fit)
                .background(Color.black)
                .cornerRadius(8)
                .padding()

            Divider()

            // Audio visualization
            AudioVisualizerView(audioState: renderEngine.audioManager.state)
                .frame(height: 60)
                .padding(.horizontal)

            Divider()

            // Controls
            RenderControlsView(renderEngine: renderEngine)
                .padding()
        }
    }
}

// MARK: - Tile Preview View

/// Metal-based preview of a single tile
struct TilePreviewView: View {
    let tileName: String
    @ObservedObject var renderEngine: RenderEngine

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Placeholder background
                Color.black

                // Status overlay
                VStack {
                    Text(tileName.capitalized)
                        .font(.headline)
                        .foregroundColor(.white)

                    if renderEngine.isRunning {
                        Text("Frame: \(renderEngine.frameCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text("Not Running")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
}

// MARK: - Audio Visualizer View

/// Displays audio levels as bar graph
struct AudioVisualizerView: View {
    let audioState: AudioState

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                AudioBar(label: "BASS", value: audioState.bass, color: .red)
                AudioBar(label: "LOW", value: audioState.lowMid, color: .orange)
                AudioBar(label: "MID", value: audioState.mid, color: .yellow)
                AudioBar(label: "HIGH", value: audioState.highs, color: .green)
                AudioBar(label: "LVL", value: audioState.level, color: .blue)

                Divider()
                    .frame(width: 1)
                    .background(Color.gray.opacity(0.3))
                    .padding(.horizontal, 4)

                AudioBar(label: "KICK", value: audioState.kickEnv, color: .purple)
                AudioBar(label: "E-F", value: audioState.energyFast, color: .pink)
                AudioBar(label: "E-S", value: audioState.energySlow, color: .cyan)
            }
            .padding(.horizontal, 8)
        }
    }
}

struct AudioBar: View {
    let label: String
    let value: Float
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    // Value bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: geometry.size.height * CGFloat(min(max(value, 0), 1)))
                }
            }

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Render Controls View

/// Controls for the render engine
struct RenderControlsView: View {
    @ObservedObject var renderEngine: RenderEngine

    var body: some View {
        HStack(spacing: 16) {
            // Start/Stop button
            Button {
                Task {
                    if renderEngine.isRunning {
                        await renderEngine.stop()
                    } else {
                        try? await renderEngine.start()
                    }
                }
            } label: {
                Label(
                    renderEngine.isRunning ? "Stop Rendering" : "Start Rendering",
                    systemImage: renderEngine.isRunning ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(renderEngine.isRunning ? .red : .green)

            Spacer()

            // Shader controls
            if renderEngine.isRunning {
                HStack(spacing: 8) {
                    Button {
                        renderEngine.shaderManager.prevShader()
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Text(renderEngine.shaderManager.state.current?.name ?? "No Shader")
                        .font(.caption)
                        .frame(minWidth: 100)

                    Button {
                        renderEngine.shaderManager.nextShader()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
    }
}

// MARK: - Rendering Tab View

/// Full rendering tab for the sidebar
struct RenderingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var renderEngine = RenderEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Main preview
                GroupBox("Visual Output") {
                    RenderPreviewView(renderEngine: renderEngine)
                }

                // Shader browser
                GroupBox("Shaders") {
                    ShaderListView(shaderManager: renderEngine.shaderManager)
                }

                // Text state
                GroupBox("Text Overlays") {
                    TextStateView(textManager: renderEngine.textManager)
                }
            }
            .padding()
        }
        .onAppear {
            Task {
                try? await renderEngine.start()
            }
        }
        .onDisappear {
            Task {
                await renderEngine.stop()
            }
        }
    }
}

// MARK: - Shader List View

struct ShaderListView: View {
    @ObservedObject var shaderManager: ShaderStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Available: \(shaderManager.availableShaders.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Load Directory") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false

                    if panel.runModal() == .OK, let url = panel.url {
                        shaderManager.loadShaderDirectory(url)
                    }
                }
                .font(.caption)
            }

            if !shaderManager.availableShaders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shaderManager.availableShaders) { shader in
                            ShaderChip(
                                name: shader.name,
                                isSelected: shaderManager.state.current?.name == shader.name
                            ) {
                                shaderManager.selectShader(name: shader.name)
                            }
                        }
                    }
                }
            } else {
                Text("No shaders loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
    }
}

struct ShaderChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text State View

struct TextStateView: View {
    @ObservedObject var textManager: TextStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Song info
            HStack {
                Text("Song:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(songInfoText)
                    .font(.caption)
            }

            // Lyrics
            HStack {
                Text("Lyrics:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(lyricsText)
                    .font(.caption)
                    .lineLimit(1)
            }

            // Refrain
            HStack {
                Text("Refrain:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(textManager.refrainState.text.isEmpty ? "-" : textManager.refrainState.text)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var songInfoText: String {
        let state = textManager.songInfoState
        if state.artist.isEmpty && state.title.isEmpty {
            return "-"
        }
        if !state.artist.isEmpty && !state.title.isEmpty {
            return "\(state.artist) - \(state.title)"
        }
        return state.artist.isEmpty ? state.title : state.artist
    }

    private var lyricsText: String {
        let state = textManager.lyricsState
        guard state.activeIndex >= 0 else { return "-" }
        return state.currentLine ?? "-"
    }
}

// MARK: - Preview

#Preview {
    RenderingView()
        .environmentObject(AppState())
        .frame(width: 800, height: 900)
}
