//
//  Percentage.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Foundation

nonisolated struct Percentage: Comparable, Sendable {
    let value: Double

    init(_ value: Double) {
        self.value = min(max(value, 0.0), 100.0)
    }

    init(_ value: UInt, outOf total: UInt) {
        self.init(Double(value), outOf: Double(total))
    }

    init(_ value: Double, outOf total: Double) {
        guard total > 0 else {
            self.init(0.0)
            return
        }
        self.init((value / total) * 100.0)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.value < rhs.value
    }
}
