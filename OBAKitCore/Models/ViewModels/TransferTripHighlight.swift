//
//  TransferTripHighlight.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Pure helpers that decide which departure trip (if any) should be visually
/// highlighted when a stop is opened as a transfer destination.
///
/// Kept free of UI so the selection rule can be unit-tested without hosting a
/// stop page. The redesigned stop page highlights the matching row; it does
/// not reintroduce relative NOW/−5m banner timing.
public enum TransferTripHighlight {

    /// The trip ID to highlight for `context`, or `nil` when there is no
    /// transfer / no known originating trip.
    public static func tripID(from context: TransferContext?) -> TripIdentifier? {
        context?.fromTripID
    }

    /// Whether a departure whose `tripID` is `tripID` should receive the
    /// transfer highlight for `context`.
    public static func shouldHighlight(tripID: TripIdentifier, context: TransferContext?) -> Bool {
        guard let highlighted = context?.fromTripID else { return false }
        return highlighted == tripID
    }
}
