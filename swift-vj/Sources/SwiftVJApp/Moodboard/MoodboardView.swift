// MoodboardView - Container view for the moodboard canvas and panels

import SwiftUI
import SwiftVJCore

struct MoodboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            PhaseFlowBarView()

            HSplitView {
                // Left: Library panel
                if appState.moodboardState.libraryPanelOpen {
                    MoodboardLibraryPanel()
                }

                // Center: Canvas
                MoodboardCanvasView()
                    .frame(minWidth: 400, minHeight: 300)

                // Right: Detail panel
                if appState.moodboardState.detailPanelSongId != nil {
                    MoodboardDetailPanel()
                }
            }
        }
        .onAppear {
            appState.send(.moodboard(.loadFromSongs))
        }
    }
}
