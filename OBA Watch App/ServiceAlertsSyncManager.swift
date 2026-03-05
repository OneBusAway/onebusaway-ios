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
            let decodedAlerts = try decoder.decode([WatchServiceAlert].self, from: data)
            let encodedData = try encoder.encode(decodedAlerts)
            WatchAppState.userDefaults.set(encodedData, forKey: storageKey)
            NotificationCenter.default.post(name: Self.alertsUpdatedNotification, object: nil)
        } catch {
            Logger.error("updateAlerts failed: \(error)")
        }
    }

    /// Retrieves the current list of service alerts.
    func currentAlerts() -> [WatchServiceAlert] {
        guard let data = WatchAppState.userDefaults.data(forKey: storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([WatchServiceAlert].self, from: data)
        } catch {
            Logger.error("Failed to decode service alerts: \(error)")
            return []
        }
    }
}
