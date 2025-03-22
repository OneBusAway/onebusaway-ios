//
//  WatchConnectivityService.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import Foundation
import WatchConnectivity
import Combine

class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()
    
    @Published var isReachable = false
    @Published var receivedFavorites: [Stop] = []
    
    private let session: WCSession
    
    private override init() {
        self.session = WCSession.default
        super.init()
        
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }
    
    func requestFavoritesFromPhone() {
        guard session.activationState == .activated else { return }
        
        let message = ["request": "favorites"]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
    
    func sendFavoritesToPhone(_ favorites: [Stop]) {
        guard session.activationState == .activated else { return }
        
        do {
            let data = try JSONEncoder().encode(favorites)
            let message = ["favorites": data]
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } catch {
            print("Error encoding favorites: \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let favoritesData = message["favorites"] as? Data {
                do {
                    let favorites = try JSONDecoder().decode([Stop].self, from: favoritesData)
                    self.receivedFavorites = favorites
                } catch {
                    print("Error decoding favorites: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
}

