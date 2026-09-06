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
    static var description = IntentDescription("Look up words on the desktop and see recent translations.")

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
        let translation = try await TranslatorService.translate(query, from: source, to: target)
        SearchHistory.add(query: query, translation: translation)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "\(query) → \(translation)")
    }
}

struct DeleteHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete recent lookup"
    static var openAppWhenRun = false

    @Parameter(title: "Query")
    var query: String

    init() {
        query = ""
    }

    init(query: String) {
        self.query = query
    }

    func perform() async throws -> some IntentResult {
        SearchHistory.remove(query: query)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
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
        .description("Look up a word and see your 15 most recent translations.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct TranslatorWidgetView: View {
    var entry: TranslatorEntry

    var body: some View {
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
                Button(intent: LookupIntent(source: entry.source, target: entry.target)) {
                    Text("Look up")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .tint(Color(red: 0.545, green: 0.173, blue: 0.255))
            }

            if entry.items.isEmpty {
                Text("Tap Look up, type a word, and the translation appears here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
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
                            Button(intent: DeleteHistoryIntent(query: item.query)) {
                                Text("✕")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.plain)
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
