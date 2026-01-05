import Foundation
import WatchConnectivity

final class ServiceAlertsSyncManager: NSObject, WCSessionDelegate {
    static let shared = ServiceAlertsSyncManager()
    static let alertsUpdatedNotification = Notification.Name("ServiceAlertsUpdated")
    private let storageKey = "watch.service_alerts"
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
            print("ServiceAlertsSyncManager WCSession activated successfully.")
        } else {
            didActivateSession = false
            print("ServiceAlertsSyncManager WCSession activation failed with state: \(activationState.rawValue), error: \(error?.localizedDescription ?? "unknown error")")
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("ServiceAlertsSyncManager WCSession reachability changed: \(session.isReachable ? "reachable" : "not reachable")")
    }
    func currentAlerts() -> [ServiceAlert] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([ServiceAlert].self, from: data)) ?? []
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["service_alerts"] as? Data {
            UserDefaults.standard.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: Self.alertsUpdatedNotification, object: nil)
        }
    }
}

struct ServiceAlert: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let body: String?
    let severity: String?
    let url: String?
}
