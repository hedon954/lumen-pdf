import AppKit
import SwiftUI

struct TranslationFailureCard: View {
    enum Style {
        case page
        case nested
    }

    let presentation: TranslationFailurePresentation
    let style: Style
    var tintOverride: Color?
    var onRetry: (() -> Void)?

    @State private var showsDiagnostics = false
    @State private var didCopy = false

    init(
        message: String,
        fallbackHeadline: String,
        style: Style = .page,
        tintOverride: Color? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.presentation = .parse(message, fallbackHeadline: fallbackHeadline)
        self.style = style
        self.tintOverride = tintOverride
        self.onRetry = onRetry
    }

    init(
        presentation: TranslationFailurePresentation,
        style: Style = .page,
        tintOverride: Color? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.presentation = presentation
        self.style = style
        self.tintOverride = tintOverride
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .page ? 14 : 10) {
            header
            summary
            if !presentation.highlights.isEmpty {
                highlights
            }
            if !presentation.hint.isEmpty {
                Text(presentation.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onRetry, style == .page {
                Button(action: onRetry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("translation.failure.retry")
            }
            if presentation.hasTechnicalDetails {
                diagnosticsSection
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(style == .page ? 0.07 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(style == .page ? 0.14 : 0.18), lineWidth: 0.5)
        }
    }

    private var tint: Color {
        tintOverride ?? {
            switch presentation.cause {
            case .configuration, .parsing:
                return .orange
            case .quota, .authentication, .emptyOutput, .network, .unknown:
                return .red
            }
        }()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: presentation.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.headline)
                    .font(style == .page ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presentation.channelLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var summary: some View {
        Text(presentation.summary)
            .font(.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var highlights: some View {
        FlowLayout(spacing: 8) {
            ForEach(presentation.highlights) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(fact.value)
                        .font(.caption.weight(.semibold))
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsDiagnostics.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(showsDiagnostics ? 90 : 0))
                        Text("技术详情")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if showsDiagnostics {
                    Button(action: copyDiagnostics) {
                        Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("复制完整诊断信息")
                }
            }

            if showsDiagnostics {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.diagnostics) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.label)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(fact.value)
                                .font(.caption)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let preview = presentation.rawPreview, !preview.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("原始响应")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(preview)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(presentation.rawMessage, forType: .string)
        didCopy = true
    }
}

/// Simple wrapping layout for compact fact chips inside the failure card.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 10_000
        return arrange(in: width.isFinite ? width : 10_000, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = placement.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: max(maxWidth, 0), height: y + rowHeight), frames)
    }
}
