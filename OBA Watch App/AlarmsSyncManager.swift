import Foundation
import WatchConnectivity
import OBASharedCore

final class AlarmsSyncManager {
    static let shared = AlarmsSyncManager()
    static let alarmsUpdatedNotification = Notification.Name("AlarmsUpdated")
    private let storageKey = "watch.alarms"

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAlarmsUpdated(_:)),
            name: WatchConnectivityService.alarmsUpdatedNotification,
            object: nil
        )
    }

    @objc private func handleAlarmsUpdated(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.alarmsUpdatedNotification, object: nil)
    }

    func currentAlarms() -> [AlarmItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([AlarmItem].self, from: data)) ?? []
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
