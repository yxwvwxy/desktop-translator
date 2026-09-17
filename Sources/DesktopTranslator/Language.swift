import AppIntents
import Foundation
import NaturalLanguage

enum Language: String, Codable, CaseIterable, AppEnum {
    case en
    case zh
    case es
    case ja
    case fr

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Language"

    static var caseDisplayRepresentations: [Language: DisplayRepresentation] = [
        .en: "English",
        .zh: "Chinese",
        .es: "Spanish",
        .ja: "Japanese",
        .fr: "French",
    ]

    var label: String {
        switch self {
        case .en: return "English"
        case .zh: return "Chinese"
        case .es: return "Spanish"
        case .ja: return "Japanese"
        case .fr: return "French"
        }
    }

    var googleCode: String {
        switch self {
        case .en: return "en"
        case .zh: return "zh-CN"
        case .es: return "es"
        case .ja: return "ja"
        case .fr: return "fr"
        }
    }

    var myMemoryCode: String {
        googleCode
    }

    static func detect(_ text: String) -> Language {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .en }

        var han = 0
        var latin = 0
        var kana = 0
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                kana += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
                han += 1
            default:
                if CharacterSet.letters.contains(scalar) {
                    latin += 1
                }
            }
        }

        if kana >= 1 { return .ja }
        if han > 0, han >= latin { return .zh }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let dominant = recognizer.dominantLanguage, let mapped = fromNL(dominant) {
            return mapped
        }
        if latin > 0 { return .en }
        if han > 0 { return .zh }
        return .en
    }

    static func pair(detecting text: String, preferredTarget: Language) -> (Language, Language) {
        let source = detect(text)
        var target = preferredTarget
        if source == target {
            target = source == .en ? .zh : .en
        }
        return (source, target)
    }

    private static func fromNL(_ language: NLLanguage) -> Language? {
        switch language {
        case .english: return .en
        case .simplifiedChinese, .traditionalChinese: return .zh
        case .spanish: return .es
        case .japanese: return .ja
        case .french: return .fr
        default: return nil
        }
    }
}
