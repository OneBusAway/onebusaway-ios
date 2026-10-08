//
//  Notification.Name.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 16/05/2020.
//

import Foundation

extension Notification.Name {
    
    // Connectivity
    public static let ConnectivityDidStart = Notification.Name("kNetworkConnectivityStartedNotification")
    public static let ConnectivityDidChange = Notification.Name("kNetworkConnectivityChangedNotification")
    public static let ConnectivityDidFinish = Notification.Name("kNetworkConnectivityFinishedNotification")
    
    // Reachability
    public static let ReachabilityDidChange = Notification.Name("kNetworkReachabilityChangedNotification")
}
