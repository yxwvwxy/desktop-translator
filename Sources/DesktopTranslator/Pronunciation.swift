import AVFoundation
import Foundation

enum Reading {
    /// Dictionary IPA when we have it, otherwise pinyin for a short Chinese phrase.
    static func display(for text: String, language: Language, dictionaryPhonetic: String?) -> String? {
        if let phonetic = dictionaryPhonetic?.trimmingCharacters(in: .whitespacesAndNewlines), !phonetic.isEmpty {
            return phonetic
        }
        guard language == .zh else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        let mutable = NSMutableString(string: trimmed)
        guard CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false) else { return nil }
        let reading = (mutable as String)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reading.isEmpty, reading.caseInsensitiveCompare(trimmed) != .orderedSame else { return nil }
        return reading
    }
}

extension Language {
    var voiceLanguage: String {
        switch self {
        case .en: return "en-US"
        case .zh: return "zh-CN"
        case .es: return "es-ES"
        case .ja: return "ja-JP"
        case .fr: return "fr-FR"
        }
    }
}

/// Plays a dictionary recording when one is available, and the system voice otherwise.
final class PronunciationSpeaker: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    /// Called on the main queue with the utterance currently playing, or nil when idle.
    var onChange: ((String?) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var token = 0
    private var activeKey: String?
    private var inFlight = false
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }()

    private var isBusy: Bool {
        inFlight || player?.isPlaying == true || synthesizer.isSpeaking
    }

    var playingKey: String? {
        isBusy ? activeKey : nil
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func stop() {
        halt()
    }

    func play(_ text: String, language: Language) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = Self.key(for: trimmed, language: language)
        if activeKey == key, isBusy {
            halt()
            return
        }
        halt()
        activeKey = key
        let current = token
        guard trimmed.count <= 180 else {
            speak(trimmed, language: language)
            return
        }
        inFlight = true
        publish()
        Task {
            let data = await Self.dictionaryAudio(trimmed, session: self.session)
            await MainActor.run {
                guard current == self.token else { return }
                self.inFlight = false
                if let data, self.startAudio(data) {
                    self.publish()
                    return
                }
                self.speak(trimmed, language: language)
            }
        }
    }

    static func key(for text: String, language: Language) -> String {
        "\(language.rawValue)\u{0}\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func halt() {
        token += 1
        activeKey = nil
        inFlight = false
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        publish()
    }

    private func speak(_ text: String, language: Language) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        synthesizer.speak(utterance)
        publish()
    }

    private func startAudio(_ data: Data) -> Bool {
        guard let audio = try? AVAudioPlayer(data: data) else { return false }
        audio.delegate = self
        player = audio
        return audio.play()
    }

    private func voice(for language: Language) -> AVSpeechSynthesisVoice? {
        let code = language.voiceLanguage
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let exact = voices.filter { $0.language == code || $0.language.hasPrefix("\(code)-") }
        let pool = exact.isEmpty ? voices.filter { $0.language.hasPrefix(String(code.prefix(2))) } : exact
        return pool.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: code)
    }

    private func publish() {
        let key = isBusy ? activeKey : nil
        if Thread.isMainThread {
            onChange?(key)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(key)
            }
        }
    }

    private func finishIfIdle() {
        guard !isBusy else { return }
        activeKey = nil
        publish()
    }

    private static func dictionaryAudio(_ text: String, session: URLSession) async -> Data? {
        var components = URLComponents(string: "https://dict.youdao.com/dictvoice")
        components?.queryItems = [
            URLQueryItem(name: "audio", value: text),
            URLQueryItem(name: "type", value: "2"),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://dict.youdao.com/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let mime = http.mimeType,
              mime.contains("audio") || mime.contains("mpeg"),
              data.count > 200 else {
            return nil
        }
        return data
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil
            self.finishIfIdle()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.finishIfIdle()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.finishIfIdle()
        }
    }
}
