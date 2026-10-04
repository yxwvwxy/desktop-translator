import AppKit

struct SpellingIssue {
    var word: String
    var range: NSRange
    var guesses: [String]
}

final class SpellingReplacement: NSObject {
    let range: NSRange
    let word: String

    init(range: NSRange, word: String) {
        self.range = range
        self.word = word
    }
}

enum Spelling {
    /// Words the system dictionary rejects in every relevant language.
    /// A British spelling is kept when US English rejects it and UK English accepts it.
    static func issues(in text: String, language: Language, tag: Int) -> [SpellingIssue] {
        let codes = languages(for: language)
        guard let primary = codes.first else { return [] }
        let base = misspellings(in: text, language: primary, tag: tag)
        let others = codes.dropFirst().map { misspellings(in: text, language: $0, tag: tag) }
        return base.filter { issue in
            others.allSatisfy { list in
                list.contains { $0.range == issue.range || $0.word.caseInsensitiveCompare(issue.word) == .orderedSame }
            }
        }
    }

    /// A short query made only of words that are not real spellings.
    /// Nil means the query should still be translated.
    static func unrecognizedQuery(_ text: String, language: Language, tag: Int) -> [SpellingIssue]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else { return nil }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;:")) == nil else { return nil }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...3).contains(tokens.count) else { return nil }
        let cores = tokens.map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
        guard cores.allSatisfy(isCheckableWord) else { return nil }

        let found = issues(in: trimmed, language: language, tag: tag)
        let misspelled = Set(found.map { $0.word.lowercased() })
        guard cores.allSatisfy({ misspelled.contains($0.lowercased()) }) else { return nil }
        if cores.allSatisfy({ $0.first?.isUppercase == true }) && found.allSatisfy(\.guesses.isEmpty) {
            return nil
        }
        return found
    }

    private static func languages(for language: Language) -> [String] {
        switch language {
        case .es:
            return ["es"]
        case .fr:
            return ["fr"]
        case .en:
            var codes: [String] = []
            let user = NSSpellChecker.shared.language()
            if user == "en" || user.hasPrefix("en_") {
                codes.append(user)
            }
            for code in ["en_US", "en_GB"] where !codes.contains(code) {
                codes.append(code)
            }
            return codes
        case .zh, .ja:
            return []
        }
    }

    private static func misspellings(in text: String, language: String, tag: Int) -> [SpellingIssue] {
        let checker = NSSpellChecker.shared
        let ns = text as NSString
        var start = 0
        var found: [SpellingIssue] = []
        while start < ns.length {
            let range = checker.checkSpelling(
                of: text,
                startingAt: start,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: tag,
                wordCount: nil
            )
            if range.location == NSNotFound || range.length == 0 || range.location < start {
                break
            }
            let word = ns.substring(with: range)
            if !shouldIgnore(word) {
                let guesses = uniqueGuesses(checker.guesses(forWordRange: range, in: text, language: language, inSpellDocumentWithTag: tag) ?? [], excluding: word)
                found.append(SpellingIssue(word: word, range: range, guesses: guesses))
            }
            let next = range.location + max(range.length, 1)
            if next <= start { break }
            start = next
        }
        return found
    }

    private static func uniqueGuesses(_ guesses: [String], excluding word: String) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for guess in guesses {
            let key = guess.lowercased()
            guard key != word.lowercased(), seen.insert(key).inserted else { continue }
            unique.append(guess)
            if unique.count == 6 { break }
        }
        return unique
    }

    private static func isCheckableWord(_ word: String) -> Bool {
        guard word.count >= 2, !shouldIgnore(word) else { return false }
        return word.unicodeScalars.allSatisfy { scalar in
            (CharacterSet.letters.contains(scalar) && scalar.isASCII) || scalar == "'" || scalar == "-"
        }
    }

    private static func shouldIgnore(_ word: String) -> Bool {
        if word.count < 2 { return true }
        if word.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) { return true }
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let abbreviation = letters.count >= 2 && letters.count <= 5 && word == word.uppercased() && word != word.lowercased()
        return abbreviation
    }
}
