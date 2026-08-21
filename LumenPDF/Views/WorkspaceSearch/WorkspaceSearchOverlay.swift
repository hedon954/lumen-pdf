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

            VStack(alignment: .leading, spacing: 10) {
                chrome
                if shouldShowResults {
                    resultsCard
                }
            }
            .padding(.top, 36)
            .frame(width: 560)
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
        WorkspaceSearchMatcher.tokens(in: controller.query)
            .joined(separator: " ")
            .count >= WorkspaceSearchKind.minimumQueryLength
    }

    private var scrim: some View {
        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08)
            .ignoresSafeArea()
            .contentShape(Rectangle())
    }

    private var chrome: some View {
        HStack(spacing: 8) {
            searchPill
            ForEach(WorkspaceSearchKind.allCases) { kind in
                kindChip(kind)
            }
        }
    }

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索笔记、划线…", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
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
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(capsuleSurface())
    }

    private func kindChip(_ kind: WorkspaceSearchKind) -> some View {
        let isOn = controller.enabledKinds.contains(kind)
        return Button {
            controller.toggleKind(kind)
        } label: {
            Text(kind.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(capsuleSurface(emphasized: isOn))
        }
        .buttonStyle(.plain)
        .help(kindHelp(kind))
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("workspaceSearch.kind.\(kind.rawValue)")
    }

    private func kindHelp(_ kind: WorkspaceSearchKind) -> String {
        switch kind {
        case .note: return "搜索已保存的笔记"
        case .underline: return "搜索当前 PDF 的划线和高亮"
        case .word: return "搜索单词本"
        case .original: return "搜索当前 PDF 原文"
        case .explanation: return "搜索当前 AI 导读"
        }
    }

    private var resultsCard: some View {
        let hits = controller.hits
        return Group {
            if hits.isEmpty {
                Text("没有匹配结果")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                                resultRow(hit, isSelected: index == controller.selectedIndex)
                                    .id(hit.id)
                                    .onTapGesture { onOpen(hit) }
                            }
                        }
                        .padding(5)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: controller.selectedIndex) { _, index in
                        guard hits.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(hits[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(controlSurface(cornerRadius: 14))
        .accessibilityIdentifier("workspaceSearch.results")
    }

    private func resultRow(_ hit: WorkspaceSearchHit, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(hit.record.kind.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.08 : 0.05))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(hit.record.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !hit.snippet.isEmpty, hit.snippet != hit.record.title {
                    Text(hit.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(locationLine(hit.record))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("workspaceSearch.result.\(hit.id)")
    }

    private func locationLine(_ record: WorkspaceSearchRecord) -> String {
        var parts: [String] = []
        if !record.pdfName.isEmpty {
            parts.append(record.pdfName)
        }
        parts.append("P\(record.pageIndex + 1)")
        return parts.joined(separator: " · ")
    }

    private func capsuleSurface(emphasized: Bool = false) -> some View {
        let fill = colorScheme == .dark
            ? Color.white.opacity(emphasized ? 0.16 : 0.10)
            : Color.white.opacity(emphasized ? 0.98 : 0.94)
        return Capsule(style: .continuous)
            .fill(fill)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 6, y: 2)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(emphasized ? 0.20 : 0.12), lineWidth: 0.5)
            }
    }

    private func controlSurface(emphasized: Bool = false, cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill = colorScheme == .dark
            ? Color.white.opacity(emphasized ? 0.16 : 0.10)
            : Color.white.opacity(emphasized ? 0.98 : 0.94)
        return shape
            .fill(fill)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 8, y: 3)
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(emphasized ? 0.22 : 0.12),
                    lineWidth: 0.5
                )
            }
    }

    private func openSelected() {
        guard let hit = controller.selectedHit() else { return }
        onOpen(hit)
    }
}
