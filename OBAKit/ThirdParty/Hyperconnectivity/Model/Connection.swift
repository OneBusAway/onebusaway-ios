//
//  Connection.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation
import Network

protocol Path {
    var isExpensive: Bool { get }
    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool
}

extension NWPath: Path {}

public enum Connection {
    case cellular
    case disconnected
    case ethernet
    case loopback
    case other
    case wifi
    
    init(_ path: Path) {
        if path.usesInterfaceType(.wiredEthernet) {
            self = .ethernet
        } else if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.other) {
            self = .other
        } else if path.usesInterfaceType(.loopback) {
            self = .loopback
        } else {
            self = .disconnected
        }
    }
}
