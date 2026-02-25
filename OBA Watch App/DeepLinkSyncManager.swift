import Foundation
import OBAKitCore

/// Handles sending requests to the paired iPhone to open specific views or perform actions.
@MainActor
final class DeepLinkSyncManager {
    static let shared = DeepLinkSyncManager()
    
    private init() {}
    
    private func sendAction(_ action: String, data: [String: Any] = [:]) -> Bool {
        var message = data
        message["action"] = action
        return WatchAppState.shared.sendMessageToPhone(message)
    }
    
    func openStopOnPhone(stopID: String) -> Bool {
        return sendAction("open_stop", data: ["stopID": stopID])
    }
    
    func openTripOnPhone(tripID: String) -> Bool {
        return sendAction("open_trip", data: ["tripID": tripID])
    }
    
    func openAlertsOnPhone() -> Bool {
        return sendAction("open_alerts")
    }
    
    func contactDeveloperOnPhone() -> Bool {
        return sendAction("contact_developer")
    }
    
    func contactTransitOnPhone() -> Bool {
        return sendAction("contact_transit")
    }
    
    func planTripOnPhone(originLat: Double, originLon: Double, destLat: Double?, destLon: Double?) -> Bool {
        var data: [String: Any] = [
            "originLat": originLat,
            "originLon": originLon
        ]
        if let destLat = destLat, let destLon = destLon {
            data["destLat"] = destLat
            data["destLon"] = destLon
        }
        return sendAction("plan_trip", data: data)
    }
}
