// SongNodeView - A single song node tile on the moodboard canvas

import SwiftUI
import SwiftVJCore
import SongRepository

struct SongNodeView: View {
    let node: MoodboardNode
    let song: Song?
    let isSelected: Bool

    @State private var isHovered = false

    private let nodeSize: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Artwork placeholder
                artworkView

                // Phase badge
                if let phase = song?.phase {
                    phaseBadge(phase)
                }
            }

            // Title + artist overlay
            titleOverlay
        }
        .frame(width: nodeSize, height: nodeSize)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 3)
        )
        .shadow(color: isHovered ? .white.opacity(0.3) : .black.opacity(0.4), radius: isHovered ? 8 : 4)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artworkView: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func phaseBadge(_ phase: Phase) -> some View {
        Text(phase.displayName)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(song?.title ?? node.tagLabel ?? "Unknown")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Text(song?.artist ?? "")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .black.opacity(0.5)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
        .foregroundStyle(.white)
    }

    private var gradientColors: [Color] {
        guard let song else {
            return [.gray.opacity(0.6), .gray.opacity(0.3)]
        }
        let energy = song.energyScore
        let hue = 0.7 - (energy * 0.5) // blue→red as energy increases
        return [
            Color(hue: hue, saturation: 0.6, brightness: 0.5),
            Color(hue: hue + 0.1, saturation: 0.4, brightness: 0.3)
        ]
    }
}
