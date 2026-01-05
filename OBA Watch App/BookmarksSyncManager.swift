import Foundation
import WatchConnectivity

/// Handles incoming bookmark data from the paired iPhone and stores it in
/// shared UserDefaults so the watch BookmarksViewModel can consume it.
final class BookmarksSyncManager: NSObject, WCSessionDelegate {
    static let shared = BookmarksSyncManager()

    /// Notification fired whenever new bookmark data has been written.
    static let bookmarksUpdatedNotification = Notification.Name("BookmarksUpdated")

    /// Storage key used by BookmarksViewModel.
    private let storageKey = "watch.bookmarks"
    private var didActivateSession = false

    private override init() {
        super.init()
        activateSessionIfNeeded()
    }

    private func activateSessionIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
        }
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            didActivateSession = true
            print("WCSession activated successfully.")
        } else {
            didActivateSession = false
            print("WCSession activation failed with state: \(activationState.rawValue), error: \(error?.localizedDescription ?? "unknown error")")
        }
    }

    #if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession reachability changed: \(session.isReachable ? "reachable" : "not reachable")")
    }
    #endif

    /// Expect the iPhone app to send bookmark payloads using either
    /// `updateApplicationContext` or `sendMessage` with the key "bookmarks" and
    /// value being raw `Data` representing a JSON-encoded `[Bookmark]` (the
    /// watch Bookmark struct).
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleBookmarksPayload(from: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleBookmarksPayload(from: message)
    }

    // MARK: - Payload Handling

    private func handleBookmarksPayload(from dictionary: [String: Any]) {
        guard let data = dictionary[storageKey] as? Data else { return }

        // Write directly to UserDefaults used by BookmarksViewModel.
        UserDefaults.standard.set(data, forKey: storageKey)

        NotificationCenter.default.post(name: Self.bookmarksUpdatedNotification, object: nil)
    }
}
