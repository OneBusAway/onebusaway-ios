import Foundation
import OBAKitCore

/// Manages service alerts synced from the paired iPhone.
final class ServiceAlertsSyncManager {
    static let shared = ServiceAlertsSyncManager()
    static let alertsUpdatedNotification = Notification.Name("ServiceAlertsUpdated")
    private let storageKey = "watch.service_alerts"

    private init() {}

    /// Updates local service alerts from data received via WatchConnectivity.
    func updateAlerts(_ alerts: [[String: Any]]) {
        // Convert the array of dictionaries to ServiceAlert objects and encode to data
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        
        do {
            let data = try JSONSerialization.data(withJSONObject: alerts, options: [])
            let decodedAlerts = try decoder.decode([ServiceAlert].self, from: data)
            let encodedData = try encoder.encode(decodedAlerts)
            UserDefaults.standard.set(encodedData, forKey: storageKey)
            NotificationCenter.default.post(name: Self.alertsUpdatedNotification, object: nil)
        } catch {
            print("Failed to sync service alerts: \(error.localizedDescription)")
        }
    }

    /// Retrieves the current list of service alerts.
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
