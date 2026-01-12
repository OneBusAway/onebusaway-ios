import Foundation
import OBAKitCore

final class AlarmsSyncManager {
    static let shared = AlarmsSyncManager()
    static let alarmsUpdatedNotification = Notification.Name("AlarmsUpdated")
    private let storageKey = "watch.alarms"

    private init() {
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
