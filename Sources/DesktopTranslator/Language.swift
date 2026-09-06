import AppIntents
import Foundation

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
}
