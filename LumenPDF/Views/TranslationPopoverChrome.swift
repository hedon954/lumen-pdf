import SwiftUI

struct TranslationPopoverLanguagePair: View {
    let languageLabel: String
    let text: String
    let phonetic: String
    let isResult: Bool
    let isLoading: Bool
    var isFallback: Bool = false
    let speakEnabled: Bool
    let onSpeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(languageLabel)
                    .font(.caption)
                    .foregroundStyle(isResult ? Color.accentColor : Color.secondary)
                if isLoading {
                    TranslationPopoverSpinner()
                    Text(text.isEmpty ? "翻译中…" : "正在生成…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if text.isEmpty && isLoading {
                        Color.clear.frame(height: 8)
                    } else if !text.isEmpty {
                        Text(text)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(isResult ? Color.accentColor : Color.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !phonetic.isEmpty {
                        Text("[\(phonetic)]")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if isFallback {
                        Label("基础翻译", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onSpeak) {
                    Image(systemName: "play.circle")
                        .font(.title2)
                        .foregroundStyle(isResult ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!speakEnabled)
                .help("朗读")
                .accessibilityLabel(isResult ? "朗读译文" : "朗读原文")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TranslationPopoverDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct TranslationPopoverSpinner: View {
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
