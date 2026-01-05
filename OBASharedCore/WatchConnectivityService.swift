
import Foundation
import WatchConnectivity
import Combine

public class WatchConnectivityService: NSObject, WCSessionDelegate {
    public static let shared = WatchConnectivityService()
    
    @Published public var currentConfiguration: OBAURLSessionAPIClient.Configuration?
    @Published public var isSessionActive: Bool = false
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isSessionActive = (activationState == .activated)
            if let error = error {
                print("WCSession activation failed with error: \(error.localizedDescription)")
            } else if activationState == .activated {
                print("WCSession activated successfully.")
            } else {
                print("WCSession activation completed with state: \(activationState.rawValue)")
            }
        }
    }
    
#if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        // TODO: Handle session becoming inactive
    }
    
    public func sessionDidDeactivate(_ session: WCSession) {
        // TODO: Handle session deactivation
    }
#endif
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let config = message["apiConfig"] as? [String: Any],
           let baseURLString = config["baseURL"] as? String,
           let baseURL = URL(string: baseURLString) {
            let apiKey = config["apiKey"] as? String
            let minutesBefore = (config["minutesBeforeArrivals"] as? UInt) ?? 5
            let minutesAfter = (config["minutesAfterArrivals"] as? UInt) ?? 35
            let configuration = OBAURLSessionAPIClient.Configuration(
                baseURL: baseURL,
                apiKey: apiKey,
                minutesBeforeArrivals: minutesBefore,
                minutesAfterArrivals: minutesAfter
            )
            DispatchQueue.main.async {
                self.currentConfiguration = configuration
            }
            return
        }
        
        if let regionData = message["region"] as? Data {
            do {
                let payload = try JSONDecoder().decode(OBARawRegionPayload.self, from: regionData)
                let configuration = payload.toConfiguration()
                DispatchQueue.main.async {
                    self.currentConfiguration = configuration
                }
            } catch {
                print("Error decoding region payload: \(error)")
            }
        }
    }
    
    public func send(message: [String: Any]) {
        guard isSessionActive && WCSession.default.isReachable else {
            print("WCSession is not active or reachable. Message not sent.")
            return
        }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
}
