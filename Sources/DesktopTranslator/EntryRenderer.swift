import AppKit

enum EntryRenderer {
    static func placeholder() -> NSAttributedString {
        styled("Look up a word or phrase to see part of speech, translation, slang, and examples.", color: Theme.muted, font: .systemFont(ofSize: 13), italic: true)
    }

    static func error(_ message: String) -> NSAttributedString {
        styled(message, color: Theme.seal, font: .systemFont(ofSize: 13))
    }

    static func render(_ entry: DictionaryEntry) -> NSAttributedString {
        let terms = highlightTerms(for: entry)
        let result = NSMutableAttributedString()
        result.append(styled(entry.headword, color: Theme.ink, font: displayFont(size: 26, weight: .semibold)))
        if let phonetic = entry.phonetic, !phonetic.isEmpty {
            result.append(newline())
            result.append(styled(phonetic, color: Theme.muted, font: .systemFont(ofSize: 13), italic: true))
        }
        result.append(newline(8))
        result.append(sectionTitle("TRANSLATION"))
        result.append(styled(entry.translation, color: Theme.ink, font: .systemFont(ofSize: 16, weight: .medium)))

        if !entry.meanings.isEmpty {
            result.append(newline(14))
            result.append(sectionTitle("MEANINGS"))
            for meaning in entry.meanings {
                result.append(styled(meaning.partOfSpeech, color: Theme.seal, font: .systemFont(ofSize: 13, weight: .semibold), italic: true))
                result.append(newline(4))
                for (index, sense) in meaning.senses.enumerated() {
                    result.append(styled("\(index + 1). \(sense.definition)", color: Theme.ink, font: .systemFont(ofSize: 13)))
                    if let example = sense.example, !example.isEmpty {
                        result.append(newline(2))
                        result.append(highlightedExample("   “\(example)”", terms: terms))
                    }
                    result.append(newline(8))
                }
            }
        }

        if !entry.slang.isEmpty {
            result.append(newline(4))
            result.append(sectionTitle("SLANG"))
            for (index, sense) in entry.slang.enumerated() {
                result.append(styled("\(index + 1). \(sense.definition)", color: Theme.ink, font: .systemFont(ofSize: 13)))
                if let example = sense.example, !example.isEmpty {
                    result.append(newline(2))
                    result.append(highlightedExample("   “\(example)”", terms: terms))
                }
                result.append(newline(8))
            }
        }

        if !entry.examples.isEmpty {
            result.append(newline(4))
            result.append(sectionTitle("EXAMPLES"))
            for example in entry.examples {
                result.append(highlightedExample("• \(example)", terms: terms))
                result.append(newline(6))
            }
        }

        if entry.meanings.isEmpty && entry.slang.isEmpty {
            result.append(newline(12))
            result.append(styled("No dictionary or slang entry found for this phrase. The translation is shown above.", color: Theme.muted, font: .systemFont(ofSize: 12), italic: true))
        }

        return result
    }

    private static func highlightTerms(for entry: DictionaryEntry) -> [String] {
        var terms = [entry.query, entry.headword]
        terms.append(contentsOf: entry.query.split(whereSeparator: \.isWhitespace).map(String.init))
        terms.append(contentsOf: entry.headword.split(whereSeparator: \.isWhitespace).map(String.init))
        var seen = Set<String>()
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { term in
                let isCJK = term.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
                return (term.count >= 2 || isCJK) && seen.insert(term.lowercased()).inserted
            }
            .sorted { $0.count > $1.count }
    }

    private static func highlightedExample(_ text: String, terms: [String]) -> NSAttributedString {
        let font = italicFont(from: .systemFont(ofSize: 13))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let result = NSMutableAttributedString(string: text, attributes: [
            .foregroundColor: Theme.muted,
            .font: font,
            .paragraphStyle: paragraph,
        ])

        for term in terms {
            let pattern = NSRegularExpression.escapedPattern(for: term)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                result.addAttributes([
                    .foregroundColor: Theme.highlight,
                    .backgroundColor: Theme.highlightWash,
                    .font: italicFont(from: .systemFont(ofSize: 13, weight: .semibold)),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: Theme.highlight,
                ], range: match.range)
            }
        }
        return result
    }

    private static func sectionTitle(_ text: String) -> NSAttributedString {
        let block = NSMutableAttributedString()
        block.append(styled(text, color: Theme.seal, font: .systemFont(ofSize: 11, weight: .semibold)))
        block.append(newline(6))
        return block
    }

    private static func styled(_ text: String, color: NSColor, font: NSFont, italic: Bool = false) -> NSAttributedString {
        let resolved = italic ? italicFont(from: font) : font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 0
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

    private static func displayFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont(name: "Iowan Old Style", size: size)
            ?? NSFont(name: "Georgia", size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func italicFont(from font: NSFont) -> NSFont {
        let manager = NSFontManager.shared
        return manager.convert(font, toHaveTrait: .italicFontMask)
    }
}
