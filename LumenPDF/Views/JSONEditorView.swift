import AppKit
import SwiftUI

struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat = 160

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.focusRingType = .exterior

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        context.coordinator.install(textView)
        context.coordinator.replaceText(text, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.minSize = NSSize(width: 0, height: minHeight)
        context.coordinator.text = $text
        if textView.string != text {
            context.coordinator.replaceText(text, in: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        private weak var textView: NSTextView?
        private var isApplyingHighlight = false

        init(text: Binding<String>) {
            self.text = text
        }

        func install(_ textView: NSTextView) {
            self.textView = textView
        }

        func replaceText(_ value: String, in textView: NSTextView) {
            let selected = textView.selectedRanges
            textView.string = value
            applyHighlight(in: textView)
            let length = (textView.string as NSString).length
            let restored = selected.compactMap { rangeValue -> NSValue? in
                var range = rangeValue.rangeValue
                range.location = min(range.location, length)
                range.length = min(range.length, max(0, length - range.location))
                return NSValue(range: range)
            }
            if !restored.isEmpty {
                textView.selectedRanges = restored
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight, let textView = notification.object as? NSTextView else { return }
            applyHighlight(in: textView)
            text.wrappedValue = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let formatted = LLMExtraConfig.prettyPrinted(textView.string)
            if formatted != textView.string {
                replaceText(formatted, in: textView)
            }
            text.wrappedValue = textView.string
        }

        private func applyHighlight(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isApplyingHighlight = true
            let font = textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let highlighted = JSONSyntaxHighlighter.attributedString(from: textView.string, font: font)
            storage.setAttributedString(highlighted)
            isApplyingHighlight = false
        }
    }
}
