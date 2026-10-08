//
//  ReachabilityResult.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation
import Network

public struct ReachabilityResult {
    
    public let connection: Connection
    public let isExpensive: Bool
    public let isReachable: Bool
    
    init(path: NWPath) {
        connection = Connection(path)
        isExpensive = path.isExpensive
        isReachable = path.status == .satisfied
    }
}
