import SwiftUI

struct WorkspaceSearchOverlay: View {
    @ObservedObject var controller: WorkspaceSearchController
    let onOpen: (WorkspaceSearchHit) -> Void

    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            scrim
                .onTapGesture { controller.dismiss() }

            VStack(spacing: 10) {
                chrome
                if shouldShowResults {
                    resultsCard
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onExitCommand { controller.dismiss() }
        .onKeyPress(.escape) {
            controller.dismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            controller.moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            controller.moveSelection(1)
            return .handled
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: controller.focusNonce) { _, _ in
            isSearchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspaceSearch.overlay")
    }

    private var shouldShowResults: Bool {
        !WorkspaceSearchMatcher.tokens(in: controller.query).isEmpty
    }

    private var scrim: some View {
        Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12)
            .ignoresSafeArea()
            .contentShape(Rectangle())
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            searchPill
            ForEach(WorkspaceSearchKind.allCases) { kind in
                kindButton(kind)
            }
        }
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索笔记、单词、划线…", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .focused($isSearchFocused)
                .onSubmit { openSelected() }
                .onKeyPress(.upArrow) {
                    controller.moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    controller.moveSelection(1)
                    return .handled
                }
                .accessibilityIdentifier("workspaceSearch.field")

            if !controller.query.isEmpty {
                Button {
                    controller.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(glassCapsule)
    }

    private func kindButton(_ kind: WorkspaceSearchKind) -> some View {
        let isOn = controller.enabledKinds.contains(kind)
        return Button {
            controller.toggleKind(kind)
        } label: {
            Image(systemName: kind.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.primary : Color.secondary.opacity(0.7))
                .frame(width: 40, height: 40)
                .background(glassCircle(isOn: isOn))
        }
        .buttonStyle(.plain)
        .help(kind.title)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("workspaceSearch.kind.\(kind.rawValue)")
    }

    private var resultsCard: some View {
        let hits = controller.hits
        return Group {
            if hits.isEmpty {
                Text("没有匹配结果")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                                resultRow(hit, isSelected: index == controller.selectedIndex)
                                    .id(hit.id)
                                    .onTapGesture { onOpen(hit) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: controller.selectedIndex) { _, index in
                        guard hits.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(hits[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(glassRect)
        .accessibilityIdentifier("workspaceSearch.results")
    }

    private func resultRow(_ hit: WorkspaceSearchHit, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hit.record.kind.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color.primary.opacity(isSelected ? 0.08 : 0.05))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(hit.record.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(hit.record.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("workspaceSearch.result.\(hit.id)")
    }

    private var glassCapsule: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
            }
    }

    private func glassCircle(isOn: Bool) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
            .overlay {
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(isOn ? 0.18 : 0.08),
                        lineWidth: isOn ? 1 : 0.6
                    )
            }
    }

    private var glassRect: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
            }
    }

    private func openSelected() {
        guard let hit = controller.selectedHit() else { return }
        onOpen(hit)
    }
}
