import AppKit

enum EntryRenderer {
    static func placeholder() -> NSAttributedString {
        styled("Type English or Chinese. Direction is detected automatically.", color: Theme.muted, font: .systemFont(ofSize: 13), italic: true)
    }

    static func error(_ message: String) -> NSAttributedString {
        styled(message, color: Theme.seal, font: .systemFont(ofSize: 13))
    }

    static func render(_ entry: DictionaryEntry) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if entry.meanings.isEmpty {
            if !entry.translation.isEmpty {
                result.append(styled(entry.translation, color: Theme.ink, font: .systemFont(ofSize: 16, weight: .medium)))
            }
        } else {
            for (index, meaning) in entry.meanings.enumerated() {
                result.append(posLine(meaning))
                if index < entry.meanings.count - 1 {
                    result.append(newline(8))
                }
            }
        }

        let examples = Array(entry.examples.prefix(2))
        if entry.targetLanguage != .en, !examples.isEmpty {
            result.append(styled("\n\n", color: Theme.ink, font: .systemFont(ofSize: 13)))
            result.append(styled("例句", color: Theme.ink, font: .systemFont(ofSize: 13, weight: .semibold)))
            for (index, example) in examples.enumerated() {
                result.append(styled("\n", color: Theme.ink, font: .systemFont(ofSize: 13)))
                result.append(exampleLine(number: index + 1, example: example, query: entry.query))
                if index < examples.count - 1 {
                    result.append(styled("\n", color: Theme.ink, font: .systemFont(ofSize: 13)))
                }
            }
        }

        return result
    }

    private static func exampleLine(number: Int, example: ExampleSentence, query: String) -> NSAttributedString {
        let line = NSMutableAttributedString()
        line.append(styled("\(number). ", color: Theme.ink, font: .systemFont(ofSize: 13, weight: .medium)))
        line.append(highlightedSentence(example.english, query: query))
        if let chinese = example.chinese, !chinese.isEmpty {
            line.append(styled("\n", color: Theme.ink, font: .systemFont(ofSize: 13)))
            line.append(styled(chinese, color: Theme.muted, font: .systemFont(ofSize: 13)))
        }
        return line
    }

    private static func highlightedSentence(_ sentence: String, query: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 13)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0
        paragraph.lineBreakMode = .byWordWrapping
        let result = NSMutableAttributedString(string: sentence, attributes: [
            .foregroundColor: Theme.ink,
            .font: font,
            .paragraphStyle: paragraph,
        ])
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return result }

        let escaped = NSRegularExpression.escapedPattern(for: needle)
        let isLatinWord = needle.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar) && scalar.isASCII || scalar == "'" || scalar == "-"
        }
        let pattern = isLatinWord ? "\\b\(escaped)\\b" : escaped
        let regex = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
            ?? (try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]))
        guard let regex else { return result }

        let matches = regex.matches(in: sentence, options: [], range: NSRange(location: 0, length: (sentence as NSString).length))
        let ranges: [NSRange]
        if matches.isEmpty, let fallback = sentence.range(of: needle, options: [.caseInsensitive]) {
            ranges = [NSRange(fallback, in: sentence)]
        } else {
            ranges = matches.map(\.range)
        }
        for range in ranges {
            result.addAttributes([
                .foregroundColor: Theme.seal,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ], range: range)
        }
        return result
    }

    private static func posLine(_ meaning: Meaning) -> NSAttributedString {
        let senses = meaning.senses.map(\.definition)
        let chinese = senses.contains(where: containsHan)
        let line = NSMutableAttributedString()
        line.append(styled(meaning.abbreviatedPOS, color: Theme.seal, font: .systemFont(ofSize: 13, weight: .semibold), italic: true))
        line.append(styled(" ", color: Theme.ink, font: .systemFont(ofSize: 13)))
        line.append(styled(senses.joined(separator: chinese ? "，" : ", "), color: Theme.ink, font: .systemFont(ofSize: 13)))
        return line
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    }

    private static func styled(_ text: String, color: NSColor, font: NSFont, italic: Bool = false) -> NSAttributedString {
        let resolved = italic ? italicFont(from: font) : font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: resolved,
            .paragraphStyle: paragraph,
        ])
    }

    private static func newline(_ after: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = after
        return NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: 4)])
    }

    private static func italicFont(from font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
}
