import Foundation

enum TranslatorError: LocalizedError {
    case empty
    case failed

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a word or phrase to look up"
        case .failed:
            return "Lookup failed. Check your network and try again."
        }
    }
}

enum TranslatorService {
    static func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslatorError.empty }

        let resolvedSource = source
        let resolvedTarget = target
        guard resolvedSource != resolvedTarget else { return trimmed }

        let chunks = chunked(trimmed, limit: 1600)
        var parts: [String] = []
        for chunk in chunks {
            if let google = try? await translateWithGoogle(chunk, from: resolvedSource, to: resolvedTarget) {
                parts.append(google)
                continue
            }
            parts.append(try await translateWithMyMemory(chunk, from: resolvedSource, to: resolvedTarget))
        }
        return parts.joined()
    }

    private static func translateWithGoogle(_ text: String, from source: Language, to target: Language) async throws -> String {
        var components = URLComponents(string: "https://clients5.google.com/translate_a/t")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: source.googleCode),
            URLQueryItem(name: "tl", value: target.googleCode),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else { throw TranslatorError.failed }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TranslatorError.failed
        }

        let translated = try parseGoogleResponse(data)
        let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TranslatorError.failed }
        return cleaned
    }

    private static func parseGoogleResponse(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)

        if let text = object as? String {
            return text
        }

        if let rows = object as? [Any] {
            let pieces = rows.compactMap { row -> String? in
                if let text = row as? String { return text }
                if let parts = row as? [Any], let text = parts.first as? String { return text }
                return nil
            }
            let joined = pieces.joined()
            if !joined.isEmpty { return joined }
        }

        throw TranslatorError.failed
    }

    static func resolvedPair(source: Language, target: Language) -> (Language, Language) {
        if source == target {
            return (source, source == .zh ? .en : .zh)
        }
        return (source, target)
    }

    private static func translateWithMyMemory(_ text: String, from source: Language, to target: Language) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(source.myMemoryCode)|\(target.myMemoryCode)"),
        ]
        guard let url = components.url else { throw TranslatorError.failed }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TranslatorError.failed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["responseData"] as? [String: Any],
              let translated = responseData["translatedText"] as? String else {
            throw TranslatorError.failed
        }

        let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TranslatorError.failed }
        return unescape(cleaned)
    }

    private static func chunked(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var current = ""
        let pieces = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for (index, piece) in pieces.enumerated() {
            let next = String(piece)
            let extra = index < pieces.count - 1 ? "\n" : ""
            if current.count + next.count + extra.count > limit, !current.isEmpty {
                chunks.append(current)
                current = next + extra
            } else {
                current += next + extra
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
