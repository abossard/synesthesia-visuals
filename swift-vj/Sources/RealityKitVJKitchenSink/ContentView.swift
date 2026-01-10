// ContentView.swift
// RealityKitVJKitchenSink
//
// Main UI layout with control panel and renderer view.

import SwiftUI
import RealityKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Left control panel
            ControlPanelView()
                .frame(width: 280)
                .background(Color.black.opacity(0.9))

            // Main renderer view
            ZStack(alignment: .topTrailing) {
                RealityViewHost()
                    .environmentObject(appState)

                // Diagnostics overlay
                DiagnosticsOverlay()
                    .padding(12)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Control Panel

struct ControlPanelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("RealityKit VJ")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.bottom, 8)

                // Look Picker
                LookPickerSection()

                Divider().background(Color.gray)

                // Global Controls
                GlobalControlsSection()

                Divider().background(Color.gray)

                // Per-Look Controls
                LookParametersSection()

                Spacer()
            }
            .padding(16)
        }
    }
}

// MARK: - Look Picker Section

struct LookPickerSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOOK")
                .font(.caption.bold())
                .foregroundColor(.gray)

            ForEach(LookType.allCases) { lookType in
                LookButton(lookType: lookType, isSelected: appState.currentLookType == lookType) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.currentLookType = lookType
                    }
                }
            }
        }
    }
}

struct LookButton: View {
    let lookType: LookType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: lookType.icon)
                    .frame(width: 20)
                Text(lookType.rawValue)
                    .font(.system(.body, design: .rounded))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .white : .gray)
    }
}

// MARK: - Global Controls Section

struct GlobalControlsSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GLOBAL")
                .font(.caption.bold())
                .foregroundColor(.gray)

            // Pause toggle
            Toggle(isOn: $appState.isPaused) {
                Label("Pause", systemImage: appState.isPaused ? "pause.fill" : "play.fill")
            }
            .toggleStyle(.switch)
            .tint(.orange)

            // Time Scale
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Time Scale")
                    Spacer()
                    Text(String(format: "%.2fx", appState.timeScale))
                        .foregroundColor(.gray)
                }
                Slider(value: $appState.timeScale, in: 0.1...3.0)
                    .tint(.blue)
            }

            // Camera Motion
            Toggle(isOn: $appState.cameraMotionEnabled) {
                Label("Camera Motion", systemImage: "video")
            }
            .toggleStyle(.switch)
            .tint(.blue)

            if appState.cameraMotionEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Camera Speed")
                        Spacer()
                        Text(String(format: "%.1f", appState.cameraMotionSpeed))
                            .foregroundColor(.gray)
                    }
                    Slider(value: $appState.cameraMotionSpeed, in: 0.0...2.0)
                        .tint(.blue)
                }
            }

            // Environment Intensity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Environment")
                    Spacer()
                    Text(String(format: "%.0f%%", appState.environmentIntensity * 100))
                        .foregroundColor(.gray)
                }
                Slider(value: $appState.environmentIntensity, in: 0.0...2.0)
                    .tint(.purple)
            }

            // Bloom Intensity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Bloom")
                    Spacer()
                    Text(String(format: "%.0f%%", appState.bloomIntensity * 100))
                        .foregroundColor(.gray)
                }
                Slider(value: $appState.bloomIntensity, in: 0.0...2.0)
                    .tint(.pink)
            }

            // Syphon toggle
            Toggle(isOn: $appState.syphonEnabled) {
                Label("Syphon Output", systemImage: "tv")
            }
            .toggleStyle(.switch)
            .tint(.green)
        }
        .font(.system(.body, design: .rounded))
        .foregroundColor(.white)
    }
}

// MARK: - Look Parameters Section

struct LookParametersSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LOOK PARAMETERS")
                .font(.caption.bold())
                .foregroundColor(.gray)

            switch appState.currentLookType {
            case .spaceDome:
                SpaceDomeParamsView(params: $appState.spaceDomeParams)
            case .water:
                WaterParamsView(params: $appState.waterParams)
            case .laserRig:
                LaserRigParamsView(params: $appState.laserRigParams)
            case .dancer:
                DancerParamsView(params: $appState.dancerParams)
            case .proceduralMesh:
                ProceduralMeshParamsView(params: $appState.proceduralMeshParams)
            }
        }
        .font(.system(.body, design: .rounded))
        .foregroundColor(.white)
    }
}

// MARK: - Per-Look Parameter Views

struct SpaceDomeParamsView: View {
    @Binding var params: SpaceDomeParams

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SliderRow(label: "Star Density", value: $params.starDensity, range: 0.1...3.0)
            SliderRow(label: "Hue Speed", value: $params.domeHueSpeed, range: 0.0...1.0)
            SliderRow(label: "Camera Drift", value: $params.cameraDriftAmplitude, range: 0.0...2.0)
            SliderRow(label: "Nebula", value: $params.nebulaIntensity, range: 0.0...1.0)
        }
    }
}

struct WaterParamsView: View {
    @Binding var params: WaterParams

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SliderRow(label: "Wave Amplitude", value: $params.waveAmplitude, range: 0.0...1.0)
            SliderRow(label: "Wave Frequency", value: $params.waveFrequency, range: 0.5...5.0)
            SliderRow(label: "Specular", value: $params.specular, range: 0.0...1.0)
            SliderRow(label: "Roughness", value: $params.roughness, range: 0.0...1.0)
        }
    }
}

struct LaserRigParamsView: View {
    @Binding var params: LaserRigParams

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Beam Count")
                Spacer()
                Text("\(params.beamCount)")
                    .foregroundColor(.gray)
            }
            Slider(value: Binding(
                get: { Double(params.beamCount) },
                set: { params.beamCount = Int($0) }
            ), in: 4...32, step: 1)
            .tint(.red)

            SliderRow(label: "Sweep Speed", value: $params.beamSweepSpeed, range: 0.1...3.0)
            SliderRow(label: "Glow", value: $params.glowIntensity, range: 0.5...5.0)
            SliderRow(label: "Color Cycle", value: $params.colorCycleSpeed, range: 0.0...2.0)
            SliderRow(label: "Fan Angle", value: $params.fanAngle, range: 20.0...120.0)
        }
    }
}

struct DancerParamsView: View {
    @Binding var params: DancerParams

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SliderRow(label: "Anim Speed", value: $params.animationSpeed, range: 0.1...3.0)
            SliderRow(label: "Scale Pulse", value: $params.scalePulse, range: 0.0...0.5)
            SliderRow(label: "Lighting", value: $params.lightingIntensity, range: 0.0...2.0)
            SliderRow(label: "Floor Reflect", value: $params.floorReflectivity, range: 0.0...1.0)
            SliderRow(label: "Rotation", value: $params.rotationSpeed, range: 0.0...1.0)
        }
    }
}

struct ProceduralMeshParamsView: View {
    @Binding var params: ProceduralMeshParams

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ribbon Length")
                Spacer()
                Text("\(params.ribbonLength)")
                    .foregroundColor(.gray)
            }
            Slider(value: Binding(
                get: { Double(params.ribbonLength) },
                set: { params.ribbonLength = Int($0) }
            ), in: 20...200, step: 10)
            .tint(.cyan)

            SliderRow(label: "Thickness", value: $params.thickness, range: 0.02...0.3)
            SliderRow(label: "Noise Scale", value: $params.noiseScale, range: 0.1...3.0)
            SliderRow(label: "Color Speed", value: $params.colorGradientSpeed, range: 0.0...1.0)

            HStack {
                Text("Wave Count")
                Spacer()
                Text("\(params.waveCount)")
                    .foregroundColor(.gray)
            }
            Slider(value: Binding(
                get: { Double(params.waveCount) },
                set: { params.waveCount = Int($0) }
            ), in: 1...6, step: 1)
            .tint(.cyan)
        }
    }
}

// MARK: - Reusable Slider Row

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundColor(.gray)
            }
            Slider(value: $value, in: range)
                .tint(.blue)
        }
    }
}

// MARK: - Diagnostics Overlay

struct DiagnosticsOverlay: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(appState.currentLookType.rawValue)
                .font(.system(.body, design: .monospaced).bold())

            Text(String(format: "%.1f FPS", appState.currentFPS))
                .font(.system(.caption, design: .monospaced))

            if appState.syphonEnabled {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Syphon")
                        .font(.system(.caption2, design: .monospaced))
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
        .foregroundColor(.white)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1440, height: 900)
}
