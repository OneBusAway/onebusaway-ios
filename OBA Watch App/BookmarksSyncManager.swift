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
        UserDefaults.standard.set(bookmarks, forKey: storageKey)
        NotificationCenter.default.post(name: Self.bookmarksUpdatedNotification, object: nil)
    }

    /// Retrieves the current list of bookmarks.
    func getBookmarks() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: storageKey) as? [[String: Any]] ?? []
    }
}
