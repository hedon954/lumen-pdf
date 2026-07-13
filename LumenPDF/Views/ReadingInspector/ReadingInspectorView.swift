import SwiftUI

struct ReadingInspectorView: View {
    @ObservedObject var model: ReadingInspectorModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: CGFloat(ReadingInspectorModel.minimumWidth))
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.mode) {
                ForEach(ReadingInspectorMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("隐藏阅读 Inspector")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .words:
            ReadingWordsPanel()
        case .notes:
            ReadingNotesPanel()
        case .ai:
            ReadingGuidePanel(model: model)
        }
    }
}

struct ReadingInspectorEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
