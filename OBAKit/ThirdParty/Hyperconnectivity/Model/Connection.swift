//
//  Connection.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation
import Network

// OBA: renamed from `Path`, which shadowed SwiftUI's `Path` throughout OBAKit.
nonisolated protocol NetworkPath {
    var isExpensive: Bool { get }
    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool
}

nonisolated extension NWPath: NetworkPath {}

nonisolated enum Connection: Sendable {
    case cellular
    case disconnected
    case ethernet
    case loopback
    case other
    case wifi

    init(_ path: some NetworkPath) {
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
