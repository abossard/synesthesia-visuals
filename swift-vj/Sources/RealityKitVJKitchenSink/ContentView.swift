// ContentView.swift - Main UI with controls and renderer
// SwiftUI interface for RealityKit VJ Kitchen Sink

import SwiftUI
import RealityKit

@MainActor
struct ContentView: View {
    @StateObject private var coordinator = SceneCoordinator()
    
    var body: some View {
        HStack(spacing: 0) {
            // Left panel - controls
            ControlPanel(coordinator: coordinator)
                .frame(width: 300)
                .background(Color(nsColor: .windowBackgroundColor))
            
            // Main area - renderer view
            VStack(spacing: 0) {
                // Diagnostics header
                HStack {
                    Text("FPS: \(coordinator.fps, specifier: "%.0f")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(coordinator.currentLookName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.black.opacity(0.3))
                
                // Renderer view
                RealityViewHost(coordinator: coordinator)
            }
        }
        .task {
            await coordinator.start()
        }
    }
}

// MARK: - Control Panel

@MainActor
struct ControlPanel: View {
    @ObservedObject var coordinator: SceneCoordinator
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("RealityKit VJ")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Kitchen Sink")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 10)
                
                Divider()
                
                // Look Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Look")
                        .font(.headline)
                    
                    Picker("", selection: $coordinator.selectedLookType) {
                        ForEach(LookType.allCases) { lookType in
                            Text(lookType.displayName).tag(lookType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                Divider()
                
                // Global Parameters
                VStack(alignment: .leading, spacing: 12) {
                    Text("Global")
                        .font(.headline)
                    
                    Toggle("Pause", isOn: $coordinator.globalParams.paused)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Scale: \(coordinator.globalParams.timeScale, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $coordinator.globalParams.timeScale, in: 0.1...3.0)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera Motion: \(coordinator.globalParams.cameraMotion, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $coordinator.globalParams.cameraMotion, in: 0.0...1.0)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment: \(coordinator.globalParams.environmentIntensity, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $coordinator.globalParams.environmentIntensity, in: 0.0...2.0)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bloom: \(coordinator.globalParams.bloomIntensity, specifier: "%.2f")")
                            .font(.caption)
                        Slider(value: $coordinator.globalParams.bloomIntensity, in: 0.0...1.0)
                    }
                    
                    Toggle("Syphon Output", isOn: $coordinator.globalParams.syphonEnabled)
                        .help("Publish frames to Syphon for OBS/Resolume")
                }
                
                Divider()
                
                // Per-Look Parameters
                LookParametersView(coordinator: coordinator)
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Look Parameters View

@MainActor
struct LookParametersView: View {
    @ObservedObject var coordinator: SceneCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Look Parameters")
                .font(.headline)
            
            switch coordinator.selectedLookType {
            case .spaceDome:
                SpaceDomeParamsView(params: $coordinator.spaceDomeParams)
            case .water:
                WaterParamsView(params: $coordinator.waterParams)
            case .laserRig:
                LaserRigParamsView(params: $coordinator.laserRigParams)
            case .dancer:
                DancerParamsView(params: $coordinator.dancerParams)
            case .proceduralMesh:
                ProceduralMeshParamsView(params: $coordinator.proceduralMeshParams)
            }
        }
    }
}

// MARK: - Individual Look Parameter Views

struct SpaceDomeParamsView: View {
    @Binding var params: SpaceDomeParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Star Density: \(params.starDensity, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.starDensity, in: 0.1...2.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Hue Speed: \(params.domeHueSpeed, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.domeHueSpeed, in: 0.0...2.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera Drift: \(params.cameraDriftAmplitude, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.cameraDriftAmplitude, in: 0.0...5.0)
            }
        }
    }
}

struct WaterParamsView: View {
    @Binding var params: WaterParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wave Amplitude: \(params.waveAmplitude, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.waveAmplitude, in: 0.0...0.5)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Wave Frequency: \(params.waveFrequency, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.waveFrequency, in: 0.1...5.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Specular: \(params.specular, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.specular, in: 0.0...1.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Roughness: \(params.roughness, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.roughness, in: 0.0...1.0)
            }
        }
    }
}

struct LaserRigParamsView: View {
    @Binding var params: LaserRigParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Beam Count: \(params.beamCount)")
                    .font(.caption)
                Slider(value: Binding(
                    get: { Double(params.beamCount) },
                    set: { params.beamCount = Int($0) }
                ), in: 4...32, step: 1)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Sweep Speed: \(params.beamSweepSpeed, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.beamSweepSpeed, in: 0.0...3.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Glow Intensity: \(params.glowIntensity, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.glowIntensity, in: 0.0...2.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Color Cycle Speed: \(params.colorCycleSpeed, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.colorCycleSpeed, in: 0.0...2.0)
            }
        }
    }
}

struct DancerParamsView: View {
    @Binding var params: DancerParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Animation Speed: \(params.animationSpeed, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.animationSpeed, in: 0.0...3.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Scale Pulse: \(params.scalePulse, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.scalePulse, in: 0.0...0.5)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Lighting: \(params.lightingIntensity, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.lightingIntensity, in: 0.0...2.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Floor Reflectivity: \(params.floorReflectivity, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.floorReflectivity, in: 0.0...1.0)
            }
        }
    }
}

struct ProceduralMeshParamsView: View {
    @Binding var params: ProceduralMeshParams
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ribbon Length: \(params.ribbonLength)")
                    .font(.caption)
                Slider(value: Binding(
                    get: { Double(params.ribbonLength) },
                    set: { params.ribbonLength = Int($0) }
                ), in: 10...200, step: 10)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Thickness: \(params.thickness, specifier: "%.3f")")
                    .font(.caption)
                Slider(value: $params.thickness, in: 0.01...0.2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Noise Scale: \(params.noiseScale, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.noiseScale, in: 0.1...5.0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Color Gradient Speed: \(params.colorGradientSpeed, specifier: "%.2f")")
                    .font(.caption)
                Slider(value: $params.colorGradientSpeed, in: 0.0...3.0)
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
