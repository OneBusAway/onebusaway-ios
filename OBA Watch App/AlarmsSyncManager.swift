import Foundation
import OBAKitCore

final class AlarmsSyncManager {
    static let shared = AlarmsSyncManager()
    static let alarmsUpdatedNotification = Notification.Name("AlarmsUpdated")
    private let storageKey = "watch.alarms"

    private init() {
    }

    func currentAlarms() -> [WatchAlarmItem] {
        guard let data = WatchAppState.userDefaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([WatchAlarmItem].self, from: data)) ?? []
    }

    /// Updates local alarms from data received via WatchConnectivity.
    func updateAlarms(_ alarms: [[String: Any]]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: alarms, options: [])
            let decoded = try JSONDecoder().decode([WatchAlarmItem].self, from: data)
            let encodedData = try JSONEncoder().encode(decoded)
            
            WatchAppState.userDefaults.set(encodedData, forKey: storageKey)
            NotificationCenter.default.post(name: Self.alarmsUpdatedNotification, object: nil)
        } catch {
            Logger.error("updateAlarms failed: \(error.localizedDescription)")
        }
    }
}
