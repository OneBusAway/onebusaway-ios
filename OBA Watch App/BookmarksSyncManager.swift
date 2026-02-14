import Foundation
import OBAKitCore

/// Handles incoming bookmark data from the paired iPhone.
final class BookmarksSyncManager {
    static let shared = BookmarksSyncManager()

    /// Notification fired whenever new bookmark data has been written.
    static let bookmarksUpdatedNotification = Notification.Name("BookmarksUpdated")

    /// Storage key used by BookmarksViewModel.
    private let storageKey = "watch.bookmarks"

    private init() {}

    /// Updates local bookmarks from data received via WatchConnectivity.
    func updateBookmarks(_ bookmarks: [[String: Any]]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: bookmarks, options: [])
            // We decode to [WatchBookmark] first to ensure compatibility, then encode back to Data
            // to match what BookmarksViewModel expects.
            let decoded = try JSONDecoder().decode([WatchBookmark].self, from: data)
            let encodedData = try JSONEncoder().encode(decoded)
            
            WatchAppState.userDefaults.set(encodedData, forKey: storageKey)
            NotificationCenter.default.post(name: Self.bookmarksUpdatedNotification, object: nil)
        } catch {
            Logger.error("updateBookmarks failed: \(error.localizedDescription)")
        }
    }

    /// Retrieves the current list of bookmarks.
    func getBookmarks() -> [WatchBookmark] {
        guard let data = WatchAppState.userDefaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([WatchBookmark].self, from: data)) ?? []
    }
}
