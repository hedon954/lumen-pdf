import AppKit
import SwiftUI

struct JSONEditorView: View {
    @Binding var text: String
    var minHeight: CGFloat = 160
    @StateObject private var session = JSONEditorSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                toolbarButton("arrow.uturn.backward", help: "撤销") {
                    session.undo()
                }
                toolbarButton("arrow.uturn.forward", help: "重做") {
                    session.redo()
                }
                toolbarButton("paintbrush", help: "格式化") {
                    session.format()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            JSONEditorTextView(text: $text, session: session, minHeight: minHeight)
                .frame(minHeight: minHeight)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func toolbarButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

@MainActor
final class JSONEditorSession: ObservableObject {
    weak var textView: NSTextView?

    func undo() {
        textView?.undoManager?.undo()
    }

    func redo() {
        textView?.undoManager?.redo()
    }

    func format() {
        guard let textView else { return }
        let pretty = LLMExtraConfig.prettyPrinted(textView.string)
        guard pretty != textView.string else { return }
        let range = NSRange(location: 0, length: (textView.string as NSString).length)
        guard textView.shouldChangeText(in: range, replacementString: pretty) else { return }
        textView.replaceCharacters(in: range, with: pretty)
        textView.didChangeText()
    }
}

private struct JSONEditorTextView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var session: JSONEditorSession
    var minHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = JSONCodeTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .exterior
        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = JSONLineNumberRulerView(scrollView: scrollView, textView: textView)
        textView.postsFrameChangedNotifications = true

        session.textView = textView
        context.coordinator.replaceText(text, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.minSize = NSSize(width: 0, height: minHeight)
        context.coordinator.text = $text
        session.textView = textView
        if textView.string != text, !textView.hasMarkedText() {
            context.coordinator.replaceText(text, in: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        private var isApplyingHighlight = false
        private var isApplyingStructuralEdit = false

        init(text: Binding<String>) {
            self.text = text
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
            if !textView.hasMarkedText() {
                applyHighlight(in: textView)
            }
            text.wrappedValue = textView.string
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if textView.hasMarkedText() {
                return false
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return insertSmartNewline(in: textView)
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return insertSpaces(in: textView)
            }
            return false
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if isApplyingStructuralEdit { return true }
            guard !textView.hasMarkedText(),
                  let replacement = replacementString,
                  replacement == "}" || replacement == "]",
                  affectedCharRange.length == 0
            else { return true }

            let nsText = textView.string as NSString
            let before = nsText.substring(to: affectedCharRange.location)
            guard let edit = JSONAutoIndenter.closingBracketEdit(
                before: before,
                bracket: Character(replacement)
            ) else { return true }

            let lineStart = affectedCharRange.location - edit.linePrefixLength
            guard lineStart >= 0 else { return true }
            let replaceRange = NSRange(location: lineStart, length: edit.linePrefixLength)
            isApplyingStructuralEdit = true
            if textView.shouldChangeText(in: replaceRange, replacementString: edit.replacement) {
                textView.replaceCharacters(in: replaceRange, with: edit.replacement)
                textView.didChangeText()
            }
            isApplyingStructuralEdit = false
            return false
        }

        private func insertSmartNewline(in textView: NSTextView) -> Bool {
            let range = textView.selectedRange()
            let nsText = textView.string as NSString
            let before = nsText.substring(to: range.location)
            let after = nsText.substring(from: range.location + range.length)
            let edit = JSONAutoIndenter.newlineEdit(before: before, after: after)
            guard textView.shouldChangeText(in: range, replacementString: edit.replacement) else {
                return false
            }
            textView.replaceCharacters(in: range, with: edit.replacement)
            textView.didChangeText()
            let cursor = range.location + edit.cursorOffset
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            return true
        }

        private func insertSpaces(in textView: NSTextView) -> Bool {
            let spaces = String(repeating: " ", count: JSONAutoIndenter.indentWidth)
            let range = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: spaces) else {
                return false
            }
            textView.replaceCharacters(in: range, with: spaces)
            textView.didChangeText()
            return true
        }

        private func applyHighlight(in textView: NSTextView) {
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            isApplyingHighlight = true
            let font = textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            storage.beginEditing()
            JSONSyntaxHighlighter.apply(to: storage, font: font)
            storage.endEditing()
            isApplyingHighlight = false
        }
    }
}

private final class JSONCodeTextView: NSTextView {
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager else { return }
        let nsText = string as NSString
        var lineRect: NSRect
        if nsText.length == 0 || layoutManager.numberOfGlyphs == 0 {
            lineRect = NSRect(
                x: 0,
                y: textContainerInset.height,
                width: bounds.width,
                height: layoutManager.defaultLineHeight(
                    for: font ?? .systemFont(ofSize: NSFont.systemFontSize)
                )
            )
        } else {
            let location = min(selectedRange().location, nsText.length)
            let glyphIndex = layoutManager.glyphIndexForCharacter(
                at: min(location, nsText.length - 1)
            )
            lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            lineRect.origin.x = 0
            lineRect.size.width = bounds.width
        }
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.22).setFill()
        lineRect.fill()
    }
}

private final class JSONLineNumberRulerView: NSRulerView {
    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 28
        textView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsRedraw),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsRedraw),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsRedraw),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func needsRedraw() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in _: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager
        else { return }

        let visible = textView.visibleRect
        let nsText = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let inset = textView.textContainerInset
        let lineHeight = layoutManager.defaultLineHeight(
            for: textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        )
        var index = 0
        var lineNumber = 1

        while index <= nsText.length {
            var lineRect: NSRect
            if nsText.length == 0 || layoutManager.numberOfGlyphs == 0 {
                lineRect = NSRect(x: 0, y: 0, width: 0, height: lineHeight)
            } else {
                let characterIndex = min(index, nsText.length - 1)
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
                lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: nil,
                    withoutAdditionalLayout: true
                )
            }
            let y = lineRect.minY + inset.height - visible.origin.y
            if y + lineRect.height >= 0, y <= visible.height {
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(x: ruleThickness - size.width - 6, y: y),
                    withAttributes: attributes
                )
            }
            if index >= nsText.length {
                break
            }
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(
                nil,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: index, length: 0)
            )
            if lineEnd == contentsEnd {
                break
            }
            index = lineEnd
            lineNumber += 1
        }
    }
}
