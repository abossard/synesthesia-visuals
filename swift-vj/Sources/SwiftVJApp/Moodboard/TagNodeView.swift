// TagNodeView - A genre, mood, or phase tag node on the moodboard canvas

import SwiftUI
import SwiftVJCore

struct TagNodeView: View {
    let node: MoodboardNode
    let isSelected: Bool
    let connectedCount: Int

    @State private var isHovered = false

    private let nodeSize: CGFloat = 100

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundStyle(categoryColor)

            Text(node.tagLabel ?? "Tag")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text(categoryLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            if connectedCount > 0 {
                Text("\(connectedCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(categoryColor.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(categoryColor)
            }
        }
        .frame(width: nodeSize, height: nodeSize)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(categoryColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? categoryColor : categoryColor.opacity(0.3), lineWidth: isSelected ? 2.5 : 1.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(categoryColor.opacity(0.2))
                        )
                )
        )
        .shadow(color: isHovered ? categoryColor.opacity(0.4) : .black.opacity(0.3), radius: isHovered ? 8 : 4)
        .onHover { isHovered = $0 }
    }

    private var categoryLabel: String {
        node.tagCategory?.rawValue.capitalized ?? "Tag"
    }

    private var iconName: String {
        switch node.tagCategory {
        case .genre: return "guitars"
        case .mood: return "heart.fill"
        case .phase: return "waveform.path.ecg"
        case .topic: return "tag.fill"
        case .custom: return "star.fill"
        case .none: return "tag"
        }
    }

    private var categoryColor: Color {
        switch node.tagCategory {
        case .genre: return .orange
        case .mood: return .purple
        case .phase: return .cyan
        case .topic: return .green
        case .custom: return .pink
        case .none: return .gray
        }
    }
}
