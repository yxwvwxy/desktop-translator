import Foundation

struct Sense {
    var definition: String
}

struct Meaning {
    var partOfSpeech: String
    var senses: [Sense]

    var abbreviatedPOS: String {
        let key = partOfSpeech.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        let short: String
        switch key {
        case "n", "noun": short = "n"
        case "v", "verb", "vt", "vi", "vtvi", "vivt": short = "v"
        case "adj", "a", "adjective": short = "adj"
        case "adv", "adverb": short = "adv"
        case "prep", "preposition": short = "prep"
        case "conj", "conjunction": short = "conj"
        case "pron", "pronoun": short = "pron"
        case "int", "interj", "interjection", "exclamation": short = "int"
        case "num", "numeral": short = "num"
        case "art", "article": short = "art"
        case "det", "determiner": short = "det"
        case "pref", "prefix": short = "pref"
        case "suf", "suffix": short = "suf"
        case "abbr", "abbreviation": short = "abbr"
        default:
            return partOfSpeech.hasSuffix(".") ? partOfSpeech : "\(partOfSpeech)."
        }
        return "\(short)."
    }

    var glossLine: String {
        let senses = self.senses.map(\.definition)
        let chinese = senses.contains { $0.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
        return "\(abbreviatedPOS) \(senses.joined(separator: chinese ? "，" : ", "))"
    }
}

struct ExampleSentence {
    var english: String
    var chinese: String?
}

struct DictionaryEntry {
    var query: String
    var headword: String
    var phonetic: String?
    var translation: String
    var sourceLanguage: Language
    var targetLanguage: Language
    var meanings: [Meaning]
    var examples: [ExampleSentence]

    var historyLine: String {
        if meanings.isEmpty {
            return translation
        }
        var seenPOS: Set<String> = []
        var glosses: [String] = []
        let chinese = meanings.contains { meaning in
            meaning.senses.contains { $0.definition.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
        }
        for meaning in meanings {
            let pos = meaning.abbreviatedPOS
            guard seenPOS.insert(pos).inserted else { continue }
            guard let raw = meaning.senses.first?.definition else { continue }
            let first = raw
                .split { $0 == "，" || $0 == "；" || $0 == "," || $0 == ";" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            guard let first else { continue }
            glosses.append(first)
            if glosses.count == 2 { break }
        }
        return glosses.joined(separator: chinese ? "；" : "; ")
    }

    var plainText: String {
        var lines: [String] = []
        if meanings.isEmpty {
            if !translation.isEmpty { lines.append(translation) }
        } else {
            for meaning in meanings {
                lines.append(meaning.glossLine)
            }
        }
        if targetLanguage != .en, !examples.isEmpty {
            lines.append("")
            lines.append("例句")
            for (index, example) in examples.prefix(2).enumerated() {
                lines.append("\(index + 1). \(example.english)")
                if let chinese = example.chinese, !chinese.isEmpty {
                    lines.append(chinese)
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum DictionaryService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func lookup(_ text: String, from source: Language, to target: Language) async throws -> DictionaryEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslatorError.empty }

        let pair = TranslatorService.resolvedPair(source: source, target: target)
        let shortEnglish = pair.0 == .en && isShortQuery(trimmed)

        async let bilingualResult = fetchGoogleBilingual(trimmed, from: pair.0, to: pair.1)
        async let youdaoResult = isShortQuery(trimmed) ? fetchYoudaoEntry(trimmed) : nil

        let bilingual = await bilingualResult
        let youdao = await youdaoResult

        var translation = bilingual?.translation ?? ""
        var meanings = mergeMeanings((youdao?.meanings ?? []) + (bilingual?.meanings ?? []))
        var examples: [ExampleSentence] = []
        if pair.1 != .en {
            examples = pickExamples((youdao?.examples ?? []) + (bilingual?.examples ?? []), query: trimmed)
            if examples.count < 2, shortEnglish, meanings.isEmpty {
                let urban = await fetchUrban(trimmed, to: pair.1)
                meanings = mergeMeanings(urban.meanings)
                examples = pickExamples(examples + urban.examples, query: trimmed)
            }
            examples = await withChinese(examples, to: pair.1)
        } else if shortEnglish, meanings.isEmpty {
            let urban = await fetchUrban(trimmed, to: pair.1)
            meanings = mergeMeanings(urban.meanings)
        }

        if translation.isEmpty {
            translation = (try? await TranslatorService.translate(trimmed, from: pair.0, to: pair.1)) ?? trimmed
        }

        return DictionaryEntry(
            query: trimmed,
            headword: firstWord(trimmed) ?? trimmed,
            phonetic: youdao?.phonetic ?? bilingual?.phonetic,
            translation: translation,
            sourceLanguage: pair.0,
            targetLanguage: pair.1,
            meanings: meanings,
            examples: Array(examples.prefix(2))
        )
    }

    private struct ParsedDictionary {
        var phonetic: String?
        var translation: String?
        var meanings: [Meaning]
        var examples: [ExampleSentence]
    }

    private static func isShortQuery(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count <= 3 && text.count <= 40
    }

    private static func mergeMeanings(_ meanings: [Meaning]) -> [Meaning] {
        var order: [String] = []
        var grouped: [String: [Sense]] = [:]
        for meaning in meanings {
            let pos = meaning.abbreviatedPOS
            if grouped[pos] == nil {
                order.append(pos)
                grouped[pos] = []
            }
            grouped[pos, default: []].append(contentsOf: meaning.senses)
        }
        return order.compactMap { pos in
            var seen = Set<String>()
            var senses: [Sense] = []
            for sense in grouped[pos] ?? [] {
                let definition = sense.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !definition.isEmpty, definition.count <= 40 else { continue }
                guard !definition.contains("。"), !definition.contains(". ") else { continue }
                let key = definition.lowercased()
                guard seen.insert(key).inserted else { continue }
                senses.append(Sense(definition: definition))
                if senses.count == 6 { break }
            }
            return senses.isEmpty ? nil : Meaning(partOfSpeech: pos, senses: senses)
        }
    }

    private static func fetchYoudaoEntry(_ term: String) async -> ParsedDictionary? {
        var components = URLComponents(string: "https://dict.youdao.com/jsonapi")!
        components.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "le", value: "en"),
            URLQueryItem(name: "dicts", value: #"{"count":2,"dicts":[["ec","blng_sents_part"]]}"#),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var meanings: [Meaning] = []
        var phonetic: String?
        if let ec = json["ec"] as? [String: Any],
           let words = ec["word"] as? [[String: Any]],
           let first = words.first {
            phonetic = [first["usphone"] as? String, first["ukphone"] as? String]
                .compactMap { $0 }
                .first { !$0.isEmpty }
                .map { "/\($0)/" }
            let trs = first["trs"] as? [[String: Any]] ?? []
            for block in trs {
                let rows = block["tr"] as? [[String: Any]] ?? []
                for row in rows {
                    guard let layer = row["l"] as? [String: Any] else { continue }
                    for line in stringList(layer["i"]) {
                        meanings.append(contentsOf: parseYoudaoExplain(line))
                    }
                }
            }
        }

        var examples: [ExampleSentence] = []
        if let blng = json["blng_sents_part"] as? [String: Any],
           let pairs = blng["sentence-pair"] as? [[String: Any]] {
            for pair in pairs {
                let english = (pair["sentence"] as? String)
                    ?? (pair["sentence-eng"] as? String).map(stripTags)
                let chinese = pair["sentence-translation"] as? String
                guard let english else { continue }
                let en = english
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !en.isEmpty, en.count <= 120 else { continue }
                let zh = chinese?
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                examples.append(ExampleSentence(english: en, chinese: (zh?.isEmpty == false) ? zh : nil))
                if examples.count == 6 { break }
            }
        }

        if meanings.isEmpty, examples.isEmpty { return nil }
        return ParsedDictionary(phonetic: phonetic, translation: nil, meanings: meanings, examples: examples)
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let text = value as? String { return [text] }
        if let items = value as? [Any] {
            return items.compactMap { $0 as? String }
        }
        return []
    }

    private static func parseYoudaoExplain(_ explain: String) -> [Meaning] {
        let text = explain.replacingOccurrences(of: "．", with: ".")
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:^|;)\s*([a-z]+)\.\s*"#) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: full)
        guard !matches.isEmpty else { return [] }

        var meanings: [Meaning] = []
        for (index, match) in matches.enumerated() {
            guard let posRange = Range(match.range(at: 1), in: text),
                  let matchRange = Range(match.range, in: text) else { continue }
            let pos = String(text[posRange])
            let start = matchRange.upperBound
            let end: String.Index
            if index + 1 < matches.count, let next = Range(matches[index + 1].range, in: text) {
                end = next.lowerBound
            } else {
                end = text.endIndex
            }
            let body = String(text[start..<end]).trimmingCharacters(in: CharacterSet(charactersIn: ";； "))
            let senses = body
                .split { $0 == "；" || $0 == ";" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("【") && $0 != "..." }
                .prefix(8)
                .map { Sense(definition: $0) }
            if !senses.isEmpty {
                meanings.append(Meaning(partOfSpeech: pos, senses: Array(senses)))
            }
        }
        return meanings
    }

    private static func fetchGoogleBilingual(_ text: String, from source: Language, to target: Language) async -> ParsedDictionary? {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: source.googleCode),
            URLQueryItem(name: "tl", value: target.googleCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "ex"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }

        var translation = ""
        if let sentences = root.first as? [Any] {
            translation = sentences.compactMap { row -> String? in
                guard let parts = row as? [Any], let text = parts.first as? String else { return nil }
                return text
            }.joined()
        }

        var meanings: [Meaning] = []
        if root.count > 1, let dictionary = root[1] as? [Any] {
            for item in dictionary {
                guard let row = item as? [Any],
                      let pos = row.first as? String,
                      row.count > 1,
                      let glosses = row[1] as? [String] else { continue }
                let senses = unique(glosses).prefix(8).map { Sense(definition: $0) }
                if !senses.isEmpty {
                    meanings.append(Meaning(partOfSpeech: pos, senses: Array(senses)))
                }
            }
        }

        let cleaned = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty || !meanings.isEmpty else { return nil }
        return ParsedDictionary(
            phonetic: nil,
            translation: cleaned.isEmpty ? nil : cleaned,
            meanings: meanings,
            examples: parseExamples(root).map { ExampleSentence(english: $0, chinese: nil) }
        )
    }

    private static func parseExamples(_ root: [Any]) -> [String] {
        var examples: [String] = []
        collectExamples(root, into: &examples, depth: 0)
        return examples
    }

    private static func collectExamples(_ value: Any, into examples: inout [String], depth: Int) {
        guard depth < 4, let rows = value as? [Any] else { return }
        if let first = rows.first as? [Any],
           let html = first.first as? String,
           html.contains("<b>") || html.contains("</b>") {
            for row in rows {
                guard let parts = row as? [Any], let raw = parts.first as? String else { continue }
                let text = stripTags(raw)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { examples.append(text) }
            }
            return
        }
        for item in rows {
            collectExamples(item, into: &examples, depth: depth + 1)
        }
    }

    private static func pickExamples(_ raw: [ExampleSentence], query: String) -> [ExampleSentence] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        var cleaned: [ExampleSentence] = []
        for item in raw {
            let english = item.english
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, english.count <= 120 else { continue }
            let key = english.lowercased()
            guard seen.insert(key).inserted else { continue }
            let chinese = item.chinese?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.append(ExampleSentence(
                english: english,
                chinese: (chinese?.isEmpty == false) ? chinese : nil
            ))
        }
        let matching = cleaned.filter { needle.isEmpty || $0.english.lowercased().contains(needle) }
        let pool = matching.count >= 2 ? matching : matching + cleaned.filter { example in
            !matching.contains { $0.english == example.english }
        }
        return Array(pool.prefix(2))
    }

    private static func withChinese(_ examples: [ExampleSentence], to target: Language) async -> [ExampleSentence] {
        var filled: [ExampleSentence] = []
        for example in examples.prefix(2) {
            if let chinese = example.chinese, !chinese.isEmpty {
                filled.append(example)
                continue
            }
            let translated = (try? await TranslatorService.translate(example.english, from: .en, to: target))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            filled.append(ExampleSentence(english: example.english, chinese: translated?.isEmpty == false ? translated : nil))
        }
        return filled
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func fetchUrban(_ term: String, to target: Language) async -> ParsedDictionary {
        var components = URLComponents(string: "https://api.urbandictionary.com/v0/define")!
        components.queryItems = [URLQueryItem(name: "term", value: term)]
        guard let url = components.url else {
            return ParsedDictionary(phonetic: nil, translation: nil, meanings: [], examples: [])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["list"] as? [[String: Any]] else {
            return ParsedDictionary(phonetic: nil, translation: nil, meanings: [], examples: [])
        }

        let ranked = list.sorted { lhs, rhs in
            (lhs["thumbs_up"] as? Int ?? 0) > (rhs["thumbs_up"] as? Int ?? 0)
        }

        var glosses: [String] = []
        var examples: [ExampleSentence] = []
        for item in ranked {
            if glosses.count < 3, let definition = item["definition"] as? String {
                for piece in splitUrbanSenses(cleanUrban(definition)) {
                    if glosses.count == 3 { break }
                    glosses.append(piece)
                }
            }
            if examples.count < 2, let example = item["example"] as? String {
                let cleaned = cleanUrban(example)
                if cleaned.count >= 8, cleaned.count <= 80 {
                    examples.append(ExampleSentence(english: cleaned, chinese: nil))
                }
            }
            if glosses.count == 3, examples.count == 2 { break }
        }

        var meanings: [Meaning] = []
        if let first = glosses.first {
            let rendered = (try? await TranslatorService.translate(first, from: .en, to: target)) ?? first
            let definition = rendered
                .split { $0 == "；" || $0 == ";" || $0 == "\n" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && $0.count <= 40 && !$0.contains("。") }
            if let definition {
                meanings = [Meaning(partOfSpeech: "slang", senses: [Sense(definition: definition)])]
            }
        }

        return ParsedDictionary(phonetic: nil, translation: nil, meanings: meanings, examples: examples)
    }

    private static func splitUrbanSenses(_ text: String) -> [String] {
        let pieces = text
            .replacingOccurrences(of: #"\d+[.)、]"#, with: "|", options: .regularExpression)
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && $0.count <= 80 }
        if pieces.count >= 2 { return Array(pieces.prefix(3)) }
        if text.count <= 80 { return [text] }
        if let comma = text.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let first = String(text[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            if first.count >= 2, first.count <= 80 { return [first] }
        }
        return [String(text.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private static func firstWord(_ text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let key = item.lowercased()
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func cleanUrban(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\\[|\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\r\\n|\\n", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
