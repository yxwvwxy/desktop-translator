import Foundation

struct HistoryItem: Codable, Equatable {
    var query: String
    var translation: String
}

enum SearchHistory {
    static let didChange = Notification.Name("SearchHistoryDidChange")

    private static let defaultsKey = "recentLookups"
    private static let folderName = "Desktop Translator"
    private static let fileName = "history.json"

    static var folderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static var fileURL: URL {
        folderURL.appendingPathComponent(fileName)
    }

    static func items() -> [HistoryItem] {
        prepareFolder()
        downloadIfNeeded()
        if let items = readFile() {
            return items
        }
        if let migrated = migrateFromDefaults() {
            return migrated
        }
        return []
    }

    static func add(query: String, translation: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !translation.isEmpty else { return }

        var items = items().filter { $0.query.caseInsensitiveCompare(query) != .orderedSame }
        items.insert(HistoryItem(query: query, translation: translation), at: 0)
        save(items)
    }

    static func remove(query: String) {
        save(items().filter { $0.query.caseInsensitiveCompare(query) != .orderedSame })
    }

    static func remove(at index: Int) {
        var items = items()
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save(items)
    }

    private static func save(_ items: [HistoryItem]) {
        prepareFolder()
        guard let data = try? JSONEncoder().encode(items) else { return }
        let url = fileURL
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { location in
            try? data.write(to: location, options: .atomic)
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func readFile() -> [HistoryItem]? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var items: [HistoryItem]?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { location in
            guard let data = try? Data(contentsOf: location) else { return }
            items = try? JSONDecoder().decode([HistoryItem].self, from: data)
        }
        return items
    }

    private static func migrateFromDefaults() -> [HistoryItem]? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: data),
              !items.isEmpty else {
            return nil
        }
        save(items)
        return items
    }

    private static func prepareFolder() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    private static func downloadIfNeeded() {
        let url = fileURL
        var isUbiquitous: AnyObject?
        _ = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
        if (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])) != nil {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        _ = isUbiquitous
    }
}

final class HistorySync: NSObject, NSFilePresenter {
    static let shared = HistorySync()

    var presentedItemURL: URL? { SearchHistory.fileURL }
    var presentedItemOperationQueue = OperationQueue()

    func start() {
        SearchHistory.items()
        NSFileCoordinator.addFilePresenter(self)
    }

    func presentedItemDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SearchHistory.didChange, object: nil)
        }
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: SearchHistory.didChange, object: nil)
        }
        completionHandler(nil)
    }
}
