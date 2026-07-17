//
//  UncheckedSendableBox.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

/// Transfers a non-Sendable value across an isolation boundary when the sender
/// provably relinquishes ownership — e.g. handing a one-shot MapKit request
/// into a detached task and receiving its non-Sendable result back (see
/// `MapRegionManager.handleMapFeatureSelection` and
/// `MapItemViewModel.fetchScene`). The box provides no synchronization;
/// correctness rests entirely on the handoff, so keep usages to sole-owner
/// transfers.
nonisolated struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
