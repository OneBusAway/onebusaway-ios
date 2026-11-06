//
//  FakeIntentDonor.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit

/// Records each donation instead of writing to the system's store.
final class FakeIntentDonor: IntentDonor {
    /// The entity id of each stop donated, in order.
    private(set) var openedStops: [String] = []

    func donateOpenStop(_ stop: StopEntity) {
        openedStops.append(stop.id)
    }
}
