import AppKit
import SwiftUI

/// Native AppKit scrollable `NSTextView` rendering syntax-colored unified diffs in Light & Dark modes.
struct NativeDiffTextView: NSViewRepresentable {
    let diffText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: AppSpacing.small, height: AppSpacing.small)
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        applyAttributedDiff(diffText, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != diffText {
            applyAttributedDiff(diffText, to: textView)
        }
    }

    private func applyAttributedDiff(_ text: String, to textView: NSTextView) {
        let attributed = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line) + "\n"
            let color: NSColor
            let bg: NSColor
            if lineStr.hasPrefix("+") && !lineStr.hasPrefix("+++") {
                color = .systemGreen
                bg = NSColor.systemGreen.withAlphaComponent(0.10)
            } else if lineStr.hasPrefix("-") && !lineStr.hasPrefix("---") {
                color = .systemRed
                bg = NSColor.systemRed.withAlphaComponent(0.10)
            } else if lineStr.hasPrefix("@@") {
                color = .systemTeal
                bg = .clear
            } else {
                color = .labelColor
                bg = .clear
            }
            attributed.append(NSAttributedString(
                string: lineStr,
                attributes: [.font: mono, .foregroundColor: color, .backgroundColor: bg]
            ))
        }
        textView.textStorage?.setAttributedString(attributed)
    }
}
