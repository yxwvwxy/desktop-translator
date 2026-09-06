import Foundation

struct Sense {
    var definition: String
    var example: String?
}

struct Meaning {
    var partOfSpeech: String
    var senses: [Sense]
}

struct SlangSense {
    var definition: String
    var example: String?
}

struct DictionaryEntry {
    var query: String
    var headword: String
    var phonetic: String?
    var translation: String
    var sourceLanguage: Language
    var meanings: [Meaning]
    var slang: [SlangSense]
    var examples: [String]

    var plainText: String {
        var lines: [String] = [headword]
        if let phonetic, !phonetic.isEmpty { lines.append(phonetic) }
        lines.append("Translation: \(translation)")
        if !meanings.isEmpty {
            lines.append("")
            lines.append("MEANINGS")
            for meaning in meanings {
                lines.append(meaning.partOfSpeech)
                for (index, sense) in meaning.senses.enumerated() {
                    lines.append("  \(index + 1). \(sense.definition)")
                    if let example = sense.example, !example.isEmpty {
                        lines.append("     “\(example)”")
                    }
                }
            }
        }
        if !slang.isEmpty {
            lines.append("")
            lines.append("SLANG")
            for (index, sense) in slang.enumerated() {
                lines.append("  \(index + 1). \(sense.definition)")
                if let example = sense.example, !example.isEmpty {
                    lines.append("     “\(example)”")
                }
            }
        }
        if !examples.isEmpty {
            lines.append("")
            lines.append("EXAMPLES")
            for example in examples {
                lines.append("  • \(example)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum DictionaryService {
    static func lookup(_ text: String, from source: Language, to target: Language) async throws -> DictionaryEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslatorError.empty }

        let pair = TranslatorService.resolvedPair(source: source, target: target)
        let english: String
        if pair.0 == .en {
            english = trimmed
        } else {
            english = (try? await TranslatorService.translate(trimmed, from: pair.0, to: .en)) ?? trimmed
        }

        let translation: String
        if pair.1 == .en {
            translation = english
        } else {
            translation = (try? await TranslatorService.translate(trimmed, from: pair.0, to: pair.1)) ?? english
        }

        let keys = lookupKeys(from: english)
        let slangKeys = unique([trimmed] + keys)

        async let dictionaryResult = firstHit(keys, fetch: fetchDictionary)
        async let slangResult = firstHit(slangKeys, fetch: fetchUrban)

        let dictionary = await dictionaryResult
        let slang = await slangResult ?? []

        var examples: [String] = []
        examples.append(contentsOf: dictionary?.examples ?? [])
        examples.append(contentsOf: slang.compactMap(\.example))
        examples = unique(examples.filter { !$0.isEmpty }).prefix(6).map { $0 }

        let headword = dictionary?.word ?? firstWord(english) ?? english
        return DictionaryEntry(
            query: trimmed,
            headword: headword,
            phonetic: dictionary?.phonetic,
            translation: translation.isEmpty ? english : translation,
            sourceLanguage: pair.0,
            meanings: dictionary?.meanings ?? [],
            slang: Array(slang.prefix(3)),
            examples: examples
        )
    }

    private struct ParsedDictionary {
        var word: String
        var phonetic: String?
        var meanings: [Meaning]
        var examples: [String]
    }

    private static func firstHit<T>(_ keys: [String], fetch: (String) async -> T?) async -> T? {
        for key in keys {
            if let result = await fetch(key) { return result }
        }
        return nil
    }

    private static func fetchDictionary(_ term: String) async -> ParsedDictionary? {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? term
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = root.first else {
            return nil
        }

        let word = (first["word"] as? String) ?? term
        var phonetic = first["phonetic"] as? String
        if phonetic == nil || phonetic?.isEmpty == true {
            let phonetics = first["phonetics"] as? [[String: Any]] ?? []
            phonetic = phonetics.compactMap { $0["text"] as? String }.first { !$0.isEmpty }
        }

        var meanings: [Meaning] = []
        var examples: [String] = []
        let rawMeanings = first["meanings"] as? [[String: Any]] ?? []
        for raw in rawMeanings.prefix(4) {
            let pos = (raw["partOfSpeech"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawDefs = raw["definitions"] as? [[String: Any]] ?? []
            var senses: [Sense] = []
            for rawDef in rawDefs.prefix(3) {
                guard let definition = rawDef["definition"] as? String, !definition.isEmpty else { continue }
                let example = (rawDef["example"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                senses.append(Sense(definition: clean(definition), example: example.flatMap { $0.isEmpty ? nil : clean($0) }))
                if let example, !example.isEmpty { examples.append(clean(example)) }
            }
            if !senses.isEmpty {
                meanings.append(Meaning(partOfSpeech: pos.isEmpty ? "sense" : pos, senses: senses))
            }
        }

        guard !meanings.isEmpty else { return nil }
        return ParsedDictionary(word: word, phonetic: phonetic, meanings: meanings, examples: examples)
    }

    private static func fetchUrban(_ term: String) async -> [SlangSense]? {
        var components = URLComponents(string: "https://api.urbandictionary.com/v0/define")!
        components.queryItems = [URLQueryItem(name: "term", value: term)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["list"] as? [[String: Any]] else {
            return nil
        }

        let ranked = list.sorted { lhs, rhs in
            (lhs["thumbs_up"] as? Int ?? 0) > (rhs["thumbs_up"] as? Int ?? 0)
        }

        var senses: [SlangSense] = []
        for item in ranked {
            guard let definition = item["definition"] as? String else { continue }
            let cleaned = cleanUrban(definition)
            guard cleaned.count > 8 else { continue }
            let example = (item["example"] as? String).map(cleanUrban).flatMap { $0.isEmpty ? nil : $0 }
            senses.append(SlangSense(definition: cleaned, example: example))
            if senses.count == 3 { break }
        }
        return senses.isEmpty ? nil : senses
    }

    private static func lookupKeys(from english: String) -> [String] {
        let cleaned = english
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard !cleaned.isEmpty else { return [] }

        var keys = [cleaned]
        let words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1 {
            keys.append(words.prefix(min(3, words.count)).joined(separator: " "))
            keys.append(words.prefix(2).joined(separator: " "))
            if let first = words.first { keys.append(first) }
        }
        return unique(keys)
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

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
