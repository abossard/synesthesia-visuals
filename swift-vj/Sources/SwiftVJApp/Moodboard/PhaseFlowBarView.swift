// PhaseFlowBarView - Horizontal phase flow visualization bar

import SwiftUI
import SwiftVJCore
import ShaderRepository

struct PhaseFlowBarView: View {
    @EnvironmentObject var appState: AppState

    private var moodboard: MoodboardSubState { appState.moodboardState }

    var body: some View {
        HStack(spacing: 0) {
            phaseFlow
            Spacer()
            suggestButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier(A11yID.moodboardPhaseBar)
    }

    // MARK: - Phase Pills + Arrows

    @ViewBuilder
    private var phaseFlow: some View {
        let phases = displayPhases
        HStack(spacing: 4) {
            ForEach(Array(phases.enumerated()), id: \.element) { index, phaseName in
                if index > 0 {
                    arrowView
                }
                phasePill(name: phaseName, count: moodboard.phaseCounts[phaseName] ?? 0)
            }
        }
    }

    private func phasePill(name: String, count: Int) -> some View {
        let isActive = moodboard.activePhaseFilter == name
        return Button {
            if isActive {
                appState.send(.moodboard(.filterByPhase(nil)))
            } else {
                appState.send(.moodboard(.filterByPhase(name)))
            }
        } label: {
            HStack(spacing: 4) {
                Text(name.capitalized)
                    .font(.system(size: 11, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var arrowView: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private var suggestButton: some View {
        Button {
            appState.send(.moodboard(.suggestPhaseFlow))
        } label: {
            Label("Auto-suggest", systemImage: "wand.and.stars")
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Helpers

    private var displayPhases: [String] {
        if !moodboard.phaseOrder.isEmpty {
            return moodboard.phaseOrder
        }
        return Phase.allCases.map(\.rawValue)
    }
}
