// TagManagerPanel - Sidebar for managing genres, moods, phases, and custom tags

import SwiftUI
import SwiftVJCore

struct TagManagerPanel: View {
    @EnvironmentObject var appState: AppState

    @State private var mergeSourceId: String?
    @State private var renamingTagId: String?
    @State private var renameText: String = ""

    private var moodboard: MoodboardSubState { appState.moodboardState }

    private var tagEntries: [(id: String, label: String, category: TagCategory)] {
        collectTagEntries(from: moodboard.nodes)
    }

    private var groupedTags: [(category: TagCategory, tags: [(id: String, label: String, category: TagCategory)])] {
        let dict = Dictionary(grouping: tagEntries, by: \.category)
        return TagCategory.allCases.compactMap { cat in
            guard let tags = dict[cat], !tags.isEmpty else { return nil }
            return (category: cat, tags: tags)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if tagEntries.isEmpty {
                emptyState
            } else {
                tagList
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Tags", systemImage: "tag.fill")
                .font(.headline)
            Spacer()
            if mergeSourceId != nil {
                Button("Cancel Merge") {
                    mergeSourceId = nil
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Button {
                appState.send(.moodboard(.toggleTagManagerPanel))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Tag List

    private var tagList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groupedTags, id: \.category) { group in
                    categorySection(group.category, tags: group.tags)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func categorySection(_ category: TagCategory, tags: [(id: String, label: String, category: TagCategory)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: categoryIcon(category))
                    .font(.system(size: 10))
                    .foregroundStyle(categoryColor(category))
                Text(category.rawValue.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(tags.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(tags, id: \.id) { tag in
                tagRow(tag)
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: (id: String, label: String, category: TagCategory)) -> some View {
        let connectedCount = connectedSongCount(tagId: tag.id)
        let isMergeSource = mergeSourceId == tag.id
        let isMergeTarget = mergeSourceId != nil && mergeSourceId != tag.id
            && tagEntries.first(where: { $0.id == mergeSourceId })?.category == tag.category
        let isRenaming = renamingTagId == tag.id

        HStack(spacing: 6) {
            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { submitRename(tag.id) }

                Button {
                    submitRename(tag.id)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button {
                    renamingTagId = nil
                    renameText = ""
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Circle()
                    .fill(categoryColor(tag.category))
                    .frame(width: 8, height: 8)

                Text(tag.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(connectedCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, alignment: .trailing)

                // Action buttons
                if isMergeTarget {
                    Button {
                        if let src = mergeSourceId {
                            appState.send(.moodboard(.mergeTags(sourceTagId: src, targetTagId: tag.id)))
                            mergeSourceId = nil
                        }
                    } label: {
                        Text("Merge Here")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        Button {
                            appState.send(.moodboard(.selectSongsForTag(tagNodeId: tag.id)))
                        } label: {
                            Label("Select Songs", systemImage: "checkmark.circle")
                        }

                        Button {
                            appState.send(.moodboard(.focusOnTag(tagNodeId: tag.id)))
                        } label: {
                            Label("Focus", systemImage: "scope")
                        }

                        Divider()

                        Button {
                            renamingTagId = tag.id
                            renameText = tag.label
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            mergeSourceId = tag.id
                        } label: {
                            Label("Merge Into…", systemImage: "arrow.triangle.merge")
                        }

                        Divider()

                        Button(role: .destructive) {
                            appState.send(.moodboard(.removeTagNode(tag.id)))
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isMergeSource ? Color.orange.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isMergeSource ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No tags on canvas")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Add tags via the toolbar")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func connectedSongCount(tagId: String) -> Int {
        connectedSongNodeIds(tagNodeId: tagId, nodes: moodboard.nodes, edges: moodboard.edges).count
    }

    private func submitRename(_ tagId: String) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.send(.moodboard(.renameTag(tagNodeId: tagId, newLabel: trimmed)))
        renamingTagId = nil
        renameText = ""
    }

    private func categoryIcon(_ category: TagCategory) -> String {
        switch category {
        case .genre: return "guitars"
        case .mood: return "heart.fill"
        case .phase: return "waveform.path.ecg"
        case .topic: return "tag.fill"
        case .custom: return "star.fill"
        }
    }

    private func categoryColor(_ category: TagCategory) -> Color {
        switch category {
        case .genre: return .orange
        case .mood: return .purple
        case .phase: return .cyan
        case .topic: return .green
        case .custom: return .pink
        }
    }
}
