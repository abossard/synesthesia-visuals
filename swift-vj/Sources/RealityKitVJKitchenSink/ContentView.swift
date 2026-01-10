import SwiftUI

@available(macOS 15.0, *)
struct ContentView: View {
    @StateObject private var coordinator = SceneCoordinator()

    var body: some View {
        HStack(spacing: 0) {
            controlPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                .padding(12)
            Divider()
            ZStack(alignment: .bottomLeading) {
                RealityViewHost(coordinator: coordinator)
                    .ignoresSafeArea()
                diagnostics
                    .padding(10)
            }
        }
        .onAppear {
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
    }

    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("RealityKit Kitchen Sink VJ")
                    .font(.headline)

                Picker("Look", selection: $coordinator.selectedLook) {
                    ForEach(LookKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                GroupBox("Global") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Pause", isOn: $coordinator.globalParams.isPaused)
                        Slider(value: $coordinator.globalParams.timeScale, in: 0.1...2.5) {
                            Text("Time Scale")
                        }
                        HStack {
                            Text("Time Scale")
                            Spacer()
                            Text(String(format: "%.2f", coordinator.globalParams.timeScale))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $coordinator.globalParams.cameraMotion, in: 0.0...1.0) {
                            Text("Camera Motion")
                        }
                        HStack {
                            Text("Camera Motion")
                            Spacer()
                            Text(String(format: "%.2f", coordinator.globalParams.cameraMotion))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $coordinator.globalParams.environmentIntensity, in: 0.2...3.0) {
                            Text("Environment")
                        }
                        HStack {
                            Text("Environment")
                            Spacer()
                            Text(String(format: "%.2f", coordinator.globalParams.environmentIntensity))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $coordinator.globalParams.bloomIntensity, in: 0.0...2.0) {
                            Text("Bloom")
                        }
                        HStack {
                            Text("Bloom")
                            Spacer()
                            Text(String(format: "%.2f", coordinator.globalParams.bloomIntensity))
                                .foregroundStyle(.secondary)
                        }
                        Toggle("Syphon Output", isOn: $coordinator.globalParams.syphonEnabled)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Look Params") {
                    LookParamsView(coordinator: coordinator)
                }
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FPS: \(String(format: "%.1f", coordinator.fps))")
            Text("Look: \(coordinator.selectedLook.displayName)")
        }
        .font(.caption)
        .padding(8)
        .background(.black.opacity(0.5))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

@available(macOS 15.0, *)
private struct LookParamsView: View {
    @ObservedObject var coordinator: SceneCoordinator

    var body: some View {
        switch coordinator.selectedLook {
        case .spaceDome:
            SpaceDomeControls(params: $coordinator.lookParams.spaceDome)
        case .water:
            WaterControls(params: $coordinator.lookParams.water)
        case .laserRig:
            LaserRigControls(params: $coordinator.lookParams.laserRig)
        case .dancer:
            DancerControls(params: $coordinator.lookParams.dancer)
        case .proceduralMesh:
            ProceduralMeshControls(params: $coordinator.lookParams.proceduralMesh)
        }
    }
}

@available(macOS 15.0, *)
private struct SpaceDomeControls: View {
    @Binding var params: SpaceDomeParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $params.starDensity, in: 0.1...3.0)
            Text("Star Density: \(String(format: "%.2f", params.starDensity))")
                .font(.caption)
            Slider(value: $params.hueSpeed, in: 0.05...1.5)
            Text("Dome Hue Speed: \(String(format: "%.2f", params.hueSpeed))")
                .font(.caption)
            Slider(value: $params.cameraDrift, in: 0.0...2.0)
            Text("Camera Drift: \(String(format: "%.2f", params.cameraDrift))")
                .font(.caption)
        }
    }
}

@available(macOS 15.0, *)
private struct WaterControls: View {
    @Binding var params: WaterParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $params.waveAmplitude, in: 0.05...1.0)
            Text("Wave Amplitude: \(String(format: "%.2f", params.waveAmplitude))")
                .font(.caption)
            Slider(value: $params.waveFrequency, in: 0.2...4.0)
            Text("Wave Frequency: \(String(format: "%.2f", params.waveFrequency))")
                .font(.caption)
            Slider(value: $params.roughness, in: 0.05...1.0)
            Text("Roughness: \(String(format: "%.2f", params.roughness))")
                .font(.caption)
            Slider(value: $params.causticTint, in: 0.0...1.0)
            Text("Caustic Tint: \(String(format: "%.2f", params.causticTint))")
                .font(.caption)
        }
    }
}

@available(macOS 15.0, *)
private struct LaserRigControls: View {
    @Binding var params: LaserRigParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $params.beamCount, in: 6...48, step: 1)
            Text("Beam Count: \(Int(params.beamCount))")
                .font(.caption)
            Slider(value: $params.sweepSpeed, in: 0.2...3.0)
            Text("Sweep Speed: \(String(format: "%.2f", params.sweepSpeed))")
                .font(.caption)
            Slider(value: $params.glowIntensity, in: 0.2...3.0)
            Text("Glow Intensity: \(String(format: "%.2f", params.glowIntensity))")
                .font(.caption)
            Slider(value: $params.colorCycle, in: 0.0...2.0)
            Text("Color Cycle: \(String(format: "%.2f", params.colorCycle))")
                .font(.caption)
        }
    }
}

@available(macOS 15.0, *)
private struct DancerControls: View {
    @Binding var params: DancerParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $params.animationSpeed, in: 0.2...2.0)
            Text("Animation Speed: \(String(format: "%.2f", params.animationSpeed))")
                .font(.caption)
            Slider(value: $params.scalePulse, in: 0.0...0.6)
            Text("Scale Pulse: \(String(format: "%.2f", params.scalePulse))")
                .font(.caption)
            Slider(value: $params.lightingIntensity, in: 0.3...3.0)
            Text("Lighting: \(String(format: "%.2f", params.lightingIntensity))")
                .font(.caption)
            Slider(value: $params.floorReflectivity, in: 0.0...1.0)
            Text("Floor Reflectivity: \(String(format: "%.2f", params.floorReflectivity))")
                .font(.caption)
        }
    }
}

@available(macOS 15.0, *)
private struct ProceduralMeshControls: View {
    @Binding var params: ProceduralMeshParams

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $params.ribbonLength, in: 4.0...18.0)
            Text("Ribbon Length: \(String(format: "%.1f", params.ribbonLength))")
                .font(.caption)
            Slider(value: $params.thickness, in: 0.03...0.4)
            Text("Thickness: \(String(format: "%.2f", params.thickness))")
                .font(.caption)
            Slider(value: $params.noiseScale, in: 0.2...2.5)
            Text("Noise Scale: \(String(format: "%.2f", params.noiseScale))")
                .font(.caption)
            Slider(value: $params.colorSpeed, in: 0.2...2.5)
            Text("Color Speed: \(String(format: "%.2f", params.colorSpeed))")
                .font(.caption)
        }
    }
}
