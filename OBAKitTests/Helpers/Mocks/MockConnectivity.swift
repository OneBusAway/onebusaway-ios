//
//  MockConnectivity.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 5/5/20.
//

import Foundation
import OBAKit
import Connectivity

class MockConnectivity: ReachabilityProtocol {

    init() {
        status = .determining
    }

    func connected(_ callback: @escaping ReachabilityCallback) {
        //
    }

    func disconnected(_ callback: @escaping ReachabilityCallback) {
        //
    }

    func startNotifier(queue: DispatchQueue) {
        //
    }

    func stopNotifier() {
        //
    }

    var status: ConnectivityStatus

}
