import Foundation
import WatchConnectivity
import OBASharedCore

/// Handles incoming bookmark data from the paired iPhone via WatchConnectivityService.
final class BookmarksSyncManager {
    static let shared = BookmarksSyncManager()

    /// Notification fired whenever new bookmark data has been written.
    static let bookmarksUpdatedNotification = Notification.Name("BookmarksUpdated")

    /// Storage key used by BookmarksViewModel.
    private let storageKey = "watch.bookmarks"

    private init() {
        // Start observing notifications from WatchConnectivityService
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookmarksUpdated(_:)),
            name: WatchConnectivityService.bookmarksUpdatedNotification,
            object: nil
        )
    }

    @objc private func handleBookmarksUpdated(_ notification: Notification) {
        // The data is already saved to UserDefaults by WatchConnectivityService,
        // so we just need to notify any local listeners.
        NotificationCenter.default.post(name: Self.bookmarksUpdatedNotification, object: nil)
    }
}
