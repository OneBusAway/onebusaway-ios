//
//  LiveActivityDismissHint.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation

/// The "swipe to dismiss" line, shown on a rider's first Live Activity only (#1553).
///
/// The decision travels in `TripAttributes.showsDismissHint`, fixed for the
/// activity's lifetime, because the widget that draws the card can't read the
/// app's defaults.
public struct LiveActivityDismissHint {
    private let userDefaults: UserDefaults

    private static let userDefaultsKey = "LiveActivityDismissHint.shown"

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// Whether the next activity should carry the hint. Reading doesn't spend it:
    /// a request that fails leaves it for the next one.
    public var isPending: Bool {
        !userDefaults.bool(forKey: Self.userDefaultsKey)
    }

    /// Call once a request has succeeded.
    public func markShown() {
        userDefaults.set(true, forKey: Self.userDefaultsKey)
    }

    public static var text: String {
        OBALoc(
            "live_activity.dismiss_hint",
            value: "Swipe left to dismiss",
            comment: "Shown under the arrivals on a rider's first Live Activity on the Lock Screen, explaining how to remove it. The direction is the Lock Screen's swipe; in right-to-left languages it is mirrored."
        )
    }
}

#endif // os(iOS)
