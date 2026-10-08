//
//  Result.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation
import Network

public class ConnectivityResult {
    public let connection: Connection
    public var isConnected: Bool {
        isThresholdMet(successPercentage, threshold: successThreshold)
    }
    public let isExpensive: Bool
    public var state: Hyperconnectivity.State {
        Hyperconnectivity.State(connection: connection, isConnected: isConnected)
    }
    private var successfulChecks: UInt = 0
    private let successThreshold: Percentage
    private let totalChecks: UInt
    private var successPercentage: Percentage {
        Percentage(successfulChecks, outOf: totalChecks)
    }
    
    init(path: Path, successThreshold: Percentage, totalChecks: UInt) {
        connection = Connection(path)
        isExpensive = path.isExpensive
        self.successThreshold = successThreshold
        self.totalChecks = totalChecks
    }
    
    func connectivityCheck(successful: Bool) {
        if successful {
            successfulChecks += 1
        }
    }
    
    private func isThresholdMet(_ percentage: Percentage, threshold: Percentage) -> Bool {
        return percentage >= threshold
    }
}
