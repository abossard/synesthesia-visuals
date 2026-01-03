// ShaderBrowserView - Browse and select shaders
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

// Use SwiftVJCore.ShaderInfo to avoid conflict with Rendering/RenderingTypes.swift
typealias CoreShaderInfo = SwiftVJCore.ShaderInfo

struct ShaderBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedQuality: String = "ALL"
    @State private var shaders: [CoreShaderInfo] = []
    
    let qualities = ["ALL", "BEST", "GOOD", "OK", "SKIP"]
    
    var filteredShaders: [CoreShaderInfo] {
        shaders.filter { shader in
            let matchesSearch = searchText.isEmpty || 
                shader.name.localizedCaseInsensitiveContains(searchText) ||
                shader.mood.localizedCaseInsensitiveContains(searchText)
            let matchesQuality = selectedQuality == "ALL" || ratingName(shader.rating) == selectedQuality
            return matchesSearch && matchesQuality
        }
    }
    
    func ratingName(_ rating: SwiftVJCore.ShaderRating) -> String {
        switch rating {
        case .best: return "BEST"
        case .good: return "GOOD"
        case .normal: return "OK"
        case .mask: return "MASK"
        case .skip: return "SKIP"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search shaders...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                
                Picker("Quality", selection: $selectedQuality) {
                    ForEach(qualities, id: \.self) { quality in
                        Text(quality).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                
                Spacer()
                
                Text("\(filteredShaders.count) shaders")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Shader grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
                ], spacing: 16) {
                    ForEach(filteredShaders, id: \.name) { shader in
                        ShaderCard(shader: shader, isSelected: appState.selectedShader == shader.name)
                            .onTapGesture {
                                Task {
                                    await appState.selectShader(shader.name)
                                }
                            }
                    }
                }
                .padding()
            }
        }
        .task {
            await loadShaders()
        }
    }
    
    private func loadShaders() async {
        // Get shaders from module
        if let module = appState.shadersModule {
            shaders = await module.allShaders
        } else {
            // Demo data
            shaders = [
                CoreShaderInfo(name: "neon_giza", path: "", energyScore: 0.8, moodValence: 0.5, mood: "energetic", colors: ["neon", "cyan"], effects: ["geometric", "pyramid"], rating: .best),
                CoreShaderInfo(name: "fluid_noise", path: "", energyScore: 0.5, moodValence: 0.3, mood: "organic", colors: ["blue", "purple"], effects: ["fluid", "flow"], rating: .good),
                CoreShaderInfo(name: "traced_tunnel", path: "", energyScore: 0.7, moodValence: -0.3, mood: "dark", colors: ["dark", "red"], effects: ["raymarching", "tunnel"], rating: .best),
                CoreShaderInfo(name: "vortex_flythrough", path: "", energyScore: 0.9, moodValence: 0.2, mood: "psychedelic", colors: ["rainbow"], effects: ["vortex"], rating: .good),
                CoreShaderInfo(name: "stained_glass", path: "", energyScore: 0.4, moodValence: 0.6, mood: "calm", colors: ["warm"], effects: ["glass", "colorful"], rating: .normal),
                CoreShaderInfo(name: "cosmic_web", path: "", energyScore: 0.6, moodValence: 0.1, mood: "ambient", colors: ["blue", "white"], effects: ["space", "network"], rating: .best),
            ]
        }
    }
}

struct ShaderCard: View {
    let shader: CoreShaderInfo
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.4), .cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                }
            
            // Name
            Text(shader.name.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.headline)
                .lineLimit(1)
            
            // Quality badge
            HStack {
                Text(ratingName(shader.rating))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(qualityColor(shader.rating))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Spacer()
                
                // Tags - use colors array as tags
                ForEach(shader.colors.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(2)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.15) : Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    func qualityColor(_ rating: SwiftVJCore.ShaderRating) -> Color {
        switch rating {
        case .best: return .green
        case .good: return .blue
        case .normal: return .orange
        case .mask: return .gray
        case .skip: return .red
        }
    }
    
    func ratingName(_ rating: SwiftVJCore.ShaderRating) -> String {
        switch rating {
        case .best: return "BEST"
        case .good: return "GOOD"
        case .normal: return "OK"
        case .mask: return "MASK"
        case .skip: return "SKIP"
        }
    }
}

#Preview {
    ShaderBrowserView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
