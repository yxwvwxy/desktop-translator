import AppIntents
import SwiftUI
import WidgetKit

struct TranslatorEntry: TimelineEntry {
    let date: Date
    let source: Language
    let target: Language
    let items: [HistoryItem]
}

struct TranslatorProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TranslatorEntry {
        TranslatorEntry(date: Date(), source: .en, target: .zh, items: [])
    }

    func snapshot(for configuration: TranslatorWidgetIntent, in context: Context) async -> TranslatorEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: TranslatorWidgetIntent, in context: Context) async -> Timeline<TranslatorEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: TranslatorWidgetIntent) -> TranslatorEntry {
        TranslatorEntry(
            date: Date(),
            source: configuration.source,
            target: configuration.target,
            items: SearchHistory.items()
        )
    }
}

struct TranslatorWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Translator"
    static var description = IntentDescription("Look up words on the desktop without opening the app.")

    @Parameter(title: "From", default: .en)
    var source: Language

    @Parameter(title: "To", default: .zh)
    var target: Language
}

struct LookupIntent: AppIntent {
    static var title: LocalizedStringResource = "Look up"
    static var description = IntentDescription("Translate a word or phrase in the Desktop Translator widget.")
    static var openAppWhenRun = false

    @Parameter(title: "Word or phrase")
    var query: String

    @Parameter(title: "From", default: .en)
    var source: Language

    @Parameter(title: "To", default: .zh)
    var target: Language

    init() {
        query = ""
        source = .en
        target = .zh
    }

    init(query: String = "", source: Language, target: Language) {
        self.query = query
        self.source = source
        self.target = target
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $query.needsValueError("Type a word or phrase.")
        }

        let pair = Language.pair(detecting: trimmed, preferredTarget: target)
        let entry = try await DictionaryService.lookup(trimmed, from: pair.0, to: pair.1)
        let summary = entry.historyLine
        SearchHistory.add(query: entry.query, translation: summary)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(entry.query)\n\(summary)")
    }
}

struct TranslatorWidget: Widget {
    let kind = "TranslatorWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TranslatorWidgetIntent.self, provider: TranslatorProvider()) { entry in
            TranslatorWidgetView(entry: entry)
                .containerBackground(Color(red: 0.973, green: 0.957, blue: 0.933), for: .widget)
        }
        .configurationDisplayName("Desktop Translator")
        .description("Look up a word on the desktop. No need to open the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TranslatorWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TranslatorEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
        default:
            regularBody
        }
    }

    private var lookupButton: some View {
        Button(intent: LookupIntent(source: entry.source, target: entry.target)) {
            Text("Look up")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .tint(Color(red: 0.545, green: 0.173, blue: 0.255))
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Desktop Translator")
                .font(.headline)
            if let item = entry.items.first {
                Text(item.query)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.translation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text("Tap Look up to translate here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            lookupButton
        }
        .padding(4)
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desktop Translator")
                        .font(.headline)
                    Text("\(entry.source.label) → \(entry.target.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                lookupButton
            }

            if entry.items.isEmpty {
                Text("Tap Look up, type a word, and the translation stays on this widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(Array(entry.items.prefix(family == .systemLarge ? 8 : 4).enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(item.query)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.translation)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        Divider().opacity(0.25)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(4)
    }

    private var headerRow: some View {
        HStack {
            Text("Query")
            Spacer()
            Text("Translation")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color(red: 0.545, green: 0.173, blue: 0.255))
        .padding(.bottom, 2)
    }
}

@main
struct TranslatorWidgetBundle: WidgetBundle {
    var body: some Widget {
        TranslatorWidget()
    }
}
