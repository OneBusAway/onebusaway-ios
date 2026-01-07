
import Foundation
import WatchConnectivity
import Combine

public class WatchConnectivityService: NSObject, WCSessionDelegate {
    private static let _shared = WatchConnectivityService()
    
    @objc public class func shared() -> WatchConnectivityService {
        return _shared
    }
    
    // Notification names for different payload types
    public static let apiConfigUpdatedNotification = Notification.Name("OBAAPIConfigUpdated")
    public static let bookmarksUpdatedNotification = Notification.Name("OBABookmarksUpdated")
    public static let alarmsUpdatedNotification = Notification.Name("OBAAlarmsUpdated")
    public static let serviceAlertsUpdatedNotification = Notification.Name("OBAServiceAlertsUpdated")
    public static let sessionActivatedNotification = Notification.Name("OBASessionActivated")

    @Published public var currentConfiguration: OBAURLSessionAPIClient.Configuration?
    @Published public var isSessionActive: Bool = false
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            // We set the delegate even if it's already set, to ensure we are the primary delegate.
            // In a well-behaved app, only one object should be setting this.
            session.delegate = self
            if session.activationState == .notActivated {
                session.activate()
            }
        }
    }
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isSessionActive = (activationState == .activated)
            if let error = error {
                print("WCSession activation failed with error: \(error.localizedDescription)")
            } else if activationState == .activated {
                print("WCSession activated successfully.")
                NotificationCenter.default.post(name: Self.sessionActivatedNotification, object: nil)
            } else {
                print("WCSession activation completed with state: \(activationState.rawValue)")
            }
        }
    }
    
#if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        // Handle session becoming inactive
    }
    
    public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate session if needed
        WCSession.default.activate()
    }
#endif
    
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncomingMessage(applicationContext)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingMessage(message)
    }

    private func handleIncomingMessage(_ message: [String : Any]) {
        // 1. API Configuration
        if let config = message["apiConfig"] as? [String: Any],
           let baseURLString = config["baseURL"] as? String,
           let baseURL = URL(string: baseURLString) {
            let apiKey = config["apiKey"] as? String
            let minutesBefore = (config["minutesBeforeArrivals"] as? UInt) ?? 5
            let minutesAfter = (config["minutesAfterArrivals"] as? UInt) ?? 125
            let configuration = OBAURLSessionAPIClient.Configuration(
                baseURL: baseURL,
                apiKey: apiKey,
                minutesBeforeArrivals: minutesBefore,
                minutesAfterArrivals: minutesAfter
            )
            DispatchQueue.main.async {
                self.currentConfiguration = configuration
                NotificationCenter.default.post(name: Self.apiConfigUpdatedNotification, object: configuration)
            }
        }
        
        // 2. Region Data
        if let regionData = message["region"] as? Data {
            do {
                let payload = try JSONDecoder().decode(OBARawRegionPayload.self, from: regionData)
                let configuration = payload.toConfiguration()
                DispatchQueue.main.async {
                    self.currentConfiguration = configuration
                    NotificationCenter.default.post(name: Self.apiConfigUpdatedNotification, object: configuration)
                }
            } catch {
                print("Error decoding region payload: \(error)")
            }
        }

        // 3. Bookmarks
        if let bookmarksData = message["watch.bookmarks"] as? Data {
            UserDefaults.standard.set(bookmarksData, forKey: "watch.bookmarks")
            NotificationCenter.default.post(name: Self.bookmarksUpdatedNotification, object: bookmarksData)
        } else if let bookmarksArray = message["watch.bookmarks"] as? [[String: Any]] {
            // If it's already a dictionary array, encode it to data
            if let data = try? JSONSerialization.data(withJSONObject: bookmarksArray, options: []) {
                UserDefaults.standard.set(data, forKey: "watch.bookmarks")
                NotificationCenter.default.post(name: Self.bookmarksUpdatedNotification, object: data)
            }
        }

        // 4. Alarms
        if let alarmsData = message["alarms"] as? Data {
            UserDefaults.standard.set(alarmsData, forKey: "watch.alarms")
            NotificationCenter.default.post(name: Self.alarmsUpdatedNotification, object: alarmsData)
        }

        // 5. Service Alerts
        if let alertsData = message["service_alerts"] as? Data {
            UserDefaults.standard.set(alertsData, forKey: "watch.service_alerts")
            NotificationCenter.default.post(name: Self.serviceAlertsUpdatedNotification, object: alertsData)
        }
    }
    
    public func send(message: [String: Any]) {
        if !WCSession.isSupported() { return }
        let session = WCSession.default
        
        if session.activationState == .activated {
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                    print("Error sending message: \(error.localizedDescription)")
                    // Fallback to application context if message fails
                    try? session.updateApplicationContext(message)
                })
            } else {
                try? session.updateApplicationContext(message)
            }
        }
    }
}
