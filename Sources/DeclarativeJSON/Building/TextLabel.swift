import UIKit

/// A label that shows its `markdown`, or its text with a `lineHeight`, as
/// attributed text, which it builds again when the text size changes, since
/// a line height grows with the text as fonts do. Without either, it shows
/// its text as a plain label.
final class TextLabel: UILabel {
    var plainText: String? { didSet { render() } }
    var markdown: String? {
        didSet {
            // Parsed here rather than in `render`, which the other properties
            // run too.
            markdownRuns = markdown.map(Self.runs)
            render()
        }
    }
    var lineHeight: Double? { didSet { render() } }
    /// The label's `font`, read for the current text size.
    var baseFont: Theme.Font? { didSet { render() } }
    var baseColor: UIColor? { didSet { render() } }
    var alignment: NSTextAlignment = .natural { didSet { render() } }

    private var markdownRuns: [(text: String, styles: Set<TextStyle>)]?
    /// How far up the text is drawn, so that it sits in the middle of each
    /// line rather than at its bottom.
    private var shift: CGFloat = 0

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            render()
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.offsetBy(dx: 0, dy: -shift))
    }

    private func render() {
        let written = baseFont?.font(compatibleWith: traitCollection)
        shift = 0
        guard markdown != nil || lineHeight != nil else {
            attributedText = nil
            // Nil sets a label's default.
            self.font = written
            textColor = baseColor
            textAlignment = alignment
            text = plainText
            setNeedsDisplay()
            return
        }

        // A plain label's defaults.
        let font = written ?? .systemFont(ofSize: UIFont.labelFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        // As a plain label does; a paragraph style's default would wrap the
        // last line rather than end it with an ellipsis.
        paragraph.lineBreakMode = .byTruncatingTail
        let result = NSMutableAttributedString()
        let runs = markdownRuns ?? [(plainText ?? "", Set<TextStyle>())]
        for run in runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font(font, run.styles), .foregroundColor: baseColor ?? .label, .paragraphStyle: paragraph,
            ]
            if run.styles.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        if let lineHeight {
            let height = UIFontMetrics.default.scaledValue(for: CGFloat(lineHeight), compatibleWith: traitCollection)
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
            // The extra height goes above the text of each line; drawing the
            // whole text up by half of it centers every line. A baseline
            // offset would do it per run, but iOS 15 moves text twice as far
            // for it as later versions do.
            shift = max(0, (height - font.lineHeight) / 2)
        }
        attributedText = result
        setNeedsDisplay()
    }

    /// The runs of inline Markdown with their styles. Block syntax, such as a
    /// heading or a list, stays as written; a link shows its text. Text that
    /// does not parse shows as written.
    static func runs(_ markdown: String) -> [(text: String, styles: Set<TextStyle>)] {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else { return [(markdown, [])] }
        return parsed.runs.map { run in
            let intent = run.inlinePresentationIntent ?? []
            var styles: Set<TextStyle> = []
            if intent.contains(.stronglyEmphasized) { styles.insert(.bold) }
            if intent.contains(.emphasized) { styles.insert(.italic) }
            if intent.contains(.strikethrough) { styles.insert(.strikethrough) }
            if intent.contains(.code) { styles.insert(.code) }
            return (String(parsed[run.range].characters), styles)
        }
    }

    /// The label's font in the styles of a run: monospaced for code, bold,
    /// italic.
    private static func font(_ font: UIFont, _ styles: Set<TextStyle>) -> UIFont {
        var result = font
        if styles.contains(.code) {
            result = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        }
        var traits = result.fontDescriptor.symbolicTraits
        if styles.contains(.bold) { traits.insert(.traitBold) }
        if styles.contains(.italic) { traits.insert(.traitItalic) }
        guard traits != result.fontDescriptor.symbolicTraits,
              let descriptor = result.fontDescriptor.withSymbolicTraits(traits) else { return result }
        return UIFont(descriptor: descriptor, size: result.pointSize)
    }

    /// A style of inline Markdown.
    enum TextStyle: Hashable {
        case bold, italic, strikethrough, code
    }
}
