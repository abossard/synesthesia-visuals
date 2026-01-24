// KaraokeSettingsView.swift - Settings UI for karaoke configuration
// Provides sliders for all configurable parameters with presets

import SwiftUI

// MARK: - Karaoke Settings View

struct KaraokeSettingsView: View {
    @ObservedObject var karaokeEngine: KaraokeEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Enable/Disable Toggle
                enableSection

                if karaokeEngine.isEnabled {
                    // Font Sizes
                    fontSizesSection

                    // Positions
                    positionsSection

                    // Opacities
                    opacitiesSection

                    // Transition Settings
                    transitionSection

                    // Animation Mode
                    animationSection

                    // Presets
                    presetsSection

                    // Preview
                    previewSection
                }
            }
            .padding()
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        Section {
            HStack {
                Toggle("Enable Karaoke Mode", isOn: $karaokeEngine.isEnabled)
                    .toggleStyle(.switch)

                Spacer()

                if karaokeEngine.displayState.hasLyrics {
                    Text("\(karaokeEngine.displayState.totalLines) lines")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        } header: {
            Text("Karaoke Engine")
                .font(.headline)
        }
    }

    // MARK: - Font Sizes Section

    private var fontSizesSection: some View {
        Section {
            VStack(spacing: 12) {
                SliderRow(
                    label: "Current Line",
                    value: $karaokeEngine.configuration.currentFontSize,
                    range: 48...120,
                    format: "%.0f pt"
                )

                SliderRow(
                    label: "Next Line",
                    value: $karaokeEngine.configuration.nextFontSize,
                    range: 24...72,
                    format: "%.0f pt"
                )

                SliderRow(
                    label: "Previous Line",
                    value: $karaokeEngine.configuration.prevFontSize,
                    range: 18...48,
                    format: "%.0f pt"
                )
            }
        } header: {
            Text("Font Sizes")
                .font(.headline)
        }
    }

    // MARK: - Positions Section

    private var positionsSection: some View {
        Section {
            VStack(spacing: 12) {
                SliderRow(
                    label: "Previous Line Y",
                    value: $karaokeEngine.configuration.prevLineY,
                    range: 0.1...0.4,
                    format: "%.0f%%",
                    multiplier: 100
                )

                SliderRow(
                    label: "Current Line Y",
                    value: $karaokeEngine.configuration.currentLineY,
                    range: 0.35...0.65,
                    format: "%.0f%%",
                    multiplier: 100
                )

                SliderRow(
                    label: "Next Line Y",
                    value: $karaokeEngine.configuration.nextLineY,
                    range: 0.6...0.9,
                    format: "%.0f%%",
                    multiplier: 100
                )
            }
        } header: {
            Text("Positions (% from top)")
                .font(.headline)
        }
    }

    // MARK: - Opacities Section

    private var opacitiesSection: some View {
        Section {
            VStack(spacing: 12) {
                SliderRow(
                    label: "Current Line",
                    value: $karaokeEngine.configuration.currentLineOpacity,
                    range: 0.5...1.0,
                    format: "%.0f%%",
                    multiplier: 100
                )

                SliderRow(
                    label: "Next Line (dimmed)",
                    value: $karaokeEngine.configuration.nextLineOpacity,
                    range: 0.1...0.7,
                    format: "%.0f%%",
                    multiplier: 100
                )

                SliderRow(
                    label: "Previous Line",
                    value: $karaokeEngine.configuration.prevLineOpacity,
                    range: 0.0...0.5,
                    format: "%.0f%%",
                    multiplier: 100
                )
            }
        } header: {
            Text("Opacities")
                .font(.headline)
        }
    }

    // MARK: - Transition Section

    private var transitionSection: some View {
        Section {
            VStack(spacing: 12) {
                SliderRow(
                    label: "Duration",
                    value: $karaokeEngine.configuration.transitionDuration,
                    range: 0.2...1.5,
                    format: "%.2f sec"
                )

                SliderRow(
                    label: "Pre-roll",
                    value: $karaokeEngine.configuration.prerollTime,
                    range: 0.0...0.5,
                    format: "%.2f sec"
                )

                HStack {
                    Text("Easing")
                    Spacer()
                    Picker("Easing", selection: $karaokeEngine.configuration.easing) {
                        ForEach(EasingFunction.allCases, id: \.self) { easing in
                            Text(easing.rawValue).tag(easing)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }
        } header: {
            Text("Transition")
                .font(.headline)
        }
    }

    // MARK: - Animation Section

    private var animationSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Text("Animation Mode")
                    Spacer()
                    Picker("Animation", selection: $karaokeEngine.configuration.animationMode) {
                        ForEach(TextAnimationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                Text(karaokeEngine.configuration.animationMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SliderRow(
                    label: "Shadow Radius",
                    value: $karaokeEngine.configuration.textShadowRadius,
                    range: 0...12,
                    format: "%.0f"
                )

                SliderRow(
                    label: "Shadow Opacity",
                    value: $karaokeEngine.configuration.textShadowOpacity,
                    range: 0...1.0,
                    format: "%.0f%%",
                    multiplier: 100
                )
            }
        } header: {
            Text("Animation & Effects")
                .font(.headline)
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        Section {
            HStack(spacing: 12) {
                PresetButton(label: "Default") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        karaokeEngine.configuration = .default
                    }
                }

                PresetButton(label: "Compact") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        karaokeEngine.configuration = .compact
                    }
                }

                PresetButton(label: "Dramatic") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        karaokeEngine.configuration = .dramatic
                    }
                }

                PresetButton(label: "Subtle") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        karaokeEngine.configuration = .subtle
                    }
                }

                PresetButton(label: "Clean") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        karaokeEngine.configuration = .clean
                    }
                }
            }
        } header: {
            Text("Presets")
                .font(.headline)
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            VStack(spacing: 12) {
                // Live preview at 50% scale
                ZStack {
                    Color.black
                    KaraokeViewBuilder(
                        displayState: karaokeEngine.displayState.hasLyrics
                            ? karaokeEngine.displayState
                            : previewDisplayState,
                        configuration: karaokeEngine.configuration,
                        beatIntensity: 0.5
                    )
                    .scaleEffect(0.5)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

                // Test controls
                HStack(spacing: 12) {
                    Button("Load Test") {
                        karaokeEngine.loadTestLyrics()
                    }

                    Button("Prev") {
                        karaokeEngine.previousLine()
                    }

                    Button("Next") {
                        karaokeEngine.nextLine()
                    }

                    Spacer()

                    // Progress slider for testing transitions
                    HStack {
                        Text("Progress")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { karaokeEngine.displayState.transitionProgress },
                                set: { karaokeEngine.setTransitionProgressForTesting($0) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 100)
                    }
                }
                .buttonStyle(.bordered)

                // Current state info
                if karaokeEngine.displayState.hasLyrics {
                    HStack {
                        Text("Line: \(karaokeEngine.displayState.progressText)")
                        Spacer()
                        if karaokeEngine.isTransitioning {
                            Text("Transitioning...")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Preview")
                .font(.headline)
        }
    }

    // Preview state when no lyrics are loaded
    private var previewDisplayState: KaraokeDisplayState {
        KaraokeDisplayState(
            prevLine: "Previous line (fading out)",
            currentLine: "Current line in full white",
            nextLine: "Next line dimmed below",
            upcomingNextLine: nil,
            activeIndex: 1,
            totalLines: 5,
            transitionProgress: 0,
            isTransitioning: false
        )
    }
}

// MARK: - Helper Views

private struct SliderRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    let format: String
    var multiplier: V = 1

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)

            Slider(value: $value, in: range)

            Text(String(format: format, Double(value * multiplier)))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
    }
}

private struct PresetButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .frame(minWidth: 60)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Preview

#Preview("Karaoke Settings") {
    KaraokeSettingsView(karaokeEngine: {
        let engine = KaraokeEngine()
        engine.loadTestLyrics()
        return engine
    }())
    .frame(width: 500, height: 800)
}
