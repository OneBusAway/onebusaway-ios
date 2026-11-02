//
//  FakeStopIndex.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit

/// Records each call when it completes. It can hold the next call of one kind
/// until the test releases it, which opens a window in the middle of a run.
actor FakeStopIndex: StopEntityIndexing {
    enum Call: Equatable {
        case deleteAll
        case deleteAllFailed
        case index([String], priority: Int)
    }

    enum Kind {
        case deleteAll
        case index
    }

    struct DeleteFailed: Error {}

    private(set) var log: [Call] = []
    private var isHolding = false
    private var holdNext: Kind?
    private var heldCall: CheckedContinuation<Void, Never>?
    private var holdingWaiters: [CheckedContinuation<Void, Never>] = []
    private var failsNextDelete = false

    func hold(next kind: Kind) {
        holdNext = kind
    }

    /// Returns once a call is being held. Pair with a test time limit.
    func waitUntilHolding() async {
        if isHolding { return }
        await withCheckedContinuation { holdingWaiters.append($0) }
    }

    func release() {
        heldCall?.resume()
        heldCall = nil
    }

    func failNextDelete() {
        failsNextDelete = true
    }

    func deleteAll() async throws {
        await waitIfHeld(.deleteAll)
        if failsNextDelete {
            failsNextDelete = false
            log.append(.deleteAllFailed)
            throw DeleteFailed()
        }
        log.append(.deleteAll)
    }

    func index(_ entities: [StopEntity], priority: Int) async throws {
        await waitIfHeld(.index)
        log.append(.index(entities.map(\.id), priority: priority))
    }

    private func waitIfHeld(_ kind: Kind) async {
        guard holdNext == kind else { return }
        holdNext = nil
        isHolding = true
        holdingWaiters.forEach { $0.resume() }
        holdingWaiters.removeAll()
        await withCheckedContinuation { heldCall = $0 }
        isHolding = false
    }
}
