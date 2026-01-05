import Foundation
import WatchConnectivity
import OBASharedCore

final class DeepLinkSyncManager {
    static let shared = DeepLinkSyncManager()
    private init() {}
    func openStopOnPhone(stopID: String) {
        WatchConnectivityService.shared.send(message: ["openStop": stopID])
    }
    func openTripOnPhone(tripID: String) {
        WatchConnectivityService.shared.send(message: ["openTrip": tripID])
    }
    func openAlertsOnPhone() {
        WatchConnectivityService.shared.send(message: ["openAlerts": true])
    }
    func contactDeveloperOnPhone() {
        WatchConnectivityService.shared.send(message: ["contactDeveloper": true])
    }
    func contactTransitOnPhone() {
        WatchConnectivityService.shared.send(message: ["contactTransit": true])
    }
    func planTripOnPhone(originLat: Double, originLon: Double, destLat: Double?, destLon: Double?) {
        var message: [String: Any] = ["planTripOrigin": ["lat": originLat, "lon": originLon]]
        if let dlat = destLat, let dlon = destLon {
            message["planTripDestination"] = ["lat": dlat, "lon": dlon]
        }
        WatchConnectivityService.shared.send(message: message)
    }
}
