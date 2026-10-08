//
//  State.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation

public enum ConnectivityState {
    case cellularWithInternet
    case cellularWithoutInternet
    case disconnected
    case ethernetWithInternet
    case ethernetWithoutInternet
    case loopback
    case otherWithInternet
    case otherWithoutInternet
    case wifiWithInternet
    case wifiWithoutInternet
    
    init(connection: Connection, isConnected: Bool) {
        switch connection {
        case .cellular:
            self = (isConnected) ? .cellularWithInternet : .cellularWithoutInternet
        case .disconnected:
            self = .disconnected
        case .ethernet:
            self = (isConnected) ? .ethernetWithInternet : .ethernetWithoutInternet
        case .loopback:
            self = .loopback
        case .other:
            self = (isConnected) ? .otherWithInternet : .otherWithoutInternet
        case .wifi:
            self = (isConnected) ? .wifiWithInternet : .wifiWithoutInternet
        }
    }
}

extension ConnectivityState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cellularWithInternet:
            return "Cellular with Internet connectivity"
        case .cellularWithoutInternet:
            return "Cellular without Internet connectivity"
        case .disconnected:
            return "Disconnected"
        case .ethernetWithInternet:
            return "Ethernet with Internet connectivity"
        case .ethernetWithoutInternet:
            return "Ethernet without Internet connectivity"
        case .loopback:
            return "Loopback"
        case .otherWithInternet:
            return "Other with Internet connectivity"
        case .otherWithoutInternet:
            return "Other without Internet connectivity"
        case .wifiWithInternet:
            return "Wi-Fi with Internet connectivity"
        case .wifiWithoutInternet:
            return "Wi-Fi without Internet connectivity"
        }
    }
}
