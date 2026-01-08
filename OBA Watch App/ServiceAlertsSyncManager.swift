import Foundation
import WatchConnectivity
import OBASharedCore

final class ServiceAlertsSyncManager {
    static let shared = ServiceAlertsSyncManager()
    static let alertsUpdatedNotification = Notification.Name("ServiceAlertsUpdated")
    private let storageKey = "watch.service_alerts"

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAlertsUpdated(_:)),
            name: WatchConnectivityService.serviceAlertsUpdatedNotification,
            object: nil
        )
    }

    @objc private func handleAlertsUpdated(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.alertsUpdatedNotification, object: nil)
    }

    func currentAlerts() -> [ServiceAlert] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([ServiceAlert].self, from: data)) ?? []
    }
}

struct ServiceAlert: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let body: String?
    let severity: String?
    let url: String?
}
