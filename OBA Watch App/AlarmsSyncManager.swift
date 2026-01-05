import Foundation
import WatchConnectivity

final class AlarmsSyncManager: NSObject, WCSessionDelegate {
    static let shared = AlarmsSyncManager()
    static let alarmsUpdatedNotification = Notification.Name("AlarmsUpdated")
    private let storageKey = "watch.alarms"
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            didActivateSession = true
            print("AlarmsSyncManager WCSession activated successfully.")
        } else {
            didActivateSession = false
            print("AlarmsSyncManager WCSession activation failed with state: \(activationState.rawValue), error: \(error?.localizedDescription ?? "unknown error")")
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("AlarmsSyncManager WCSession reachability changed: \(session.isReachable ? "reachable" : "not reachable")")
    }
    func currentAlarms() -> [AlarmItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([AlarmItem].self, from: data)) ?? []
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["alarms"] as? Data {
            UserDefaults.standard.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: Self.alarmsUpdatedNotification, object: nil)
        }
    }
}

struct AlarmItem: Identifiable, Codable, Equatable {
    let id: String
    let stopID: String
    let routeShortName: String?
    let headsign: String?
    let scheduledTime: Date?
    let status: String?
}
