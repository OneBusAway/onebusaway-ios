//
//  Result.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation

// OBA: an immutable value built once a check has finished. Upstream published a
// class whose success count the in-flight check went on incrementing, from
// whichever thread each response arrived on.
nonisolated struct ConnectivityResult: Sendable {
    let connection: Connection
    let isConnected: Bool
    let isExpensive: Bool

    init(path: some NetworkPath, successfulChecks: UInt, totalChecks: UInt, successThreshold: Percentage) {
        connection = Connection(path)
        isConnected = Percentage(successfulChecks, outOf: totalChecks) >= successThreshold
        isExpensive = path.isExpensive
    }
}
