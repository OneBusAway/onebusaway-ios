//
//  Percentage.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation

public struct Percentage: Comparable {
    let value: Double

    public init(_ value: Double) {
        var result = value < 0.0 ? 0.0 : value
        result = result > 100.0 ? 100.0 : result
        self.value = result
    }
    
    public init(_ value: UInt, outOf total: UInt) {
        self.init(Double(value), outOf: Double(total))
    }
    
    public init(_ value: Double, outOf total: Double) {
        guard total > 0 else {
            self.init(0.0)
            return
        }
        self.init((value / total) * 100.0)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.value < rhs.value
    }
}
