//
//  MockConnectivity.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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
