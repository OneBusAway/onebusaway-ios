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
        case indexFailed([String], priority: Int)
    }

    enum Kind {
        case deleteAll
        case index
    }

    struct DeleteFailed: Error {}
    struct IndexFailed: Error {}

    private(set) var log: [Call] = []
    /// The entities of each `index` call, in order, for checks on more than the id.
    private(set) var indexed: [(entities: [StopEntity], priority: Int)] = []
    private var isHolding = false
    private var holdNext: Kind?
    private var heldCall: CheckedContinuation<Void, Never>?
    private var holdingWaiters: [CheckedContinuation<Void, Never>] = []
    private var failsNextDelete = false
    private var failsNextIndex = false

    func hold(next kind: Kind) {
        holdNext = kind
    }

    /// Returns once a call is being held. Pair with a test time limit.
    func waitUntilHolding() async {
        if isHolding { return }
        await withCheckedContinuation { holdingWaiters.append($0) }
    }

    /// Clears `isHolding` here rather than when the call resumes, so a
    /// `waitUntilHolding()` straight after waits for the next hold.
    func release() {
        heldCall?.resume()
        heldCall = nil
        isHolding = false
    }

    func failNextDelete() {
        failsNextDelete = true
    }

    func failNextIndex() {
        failsNextIndex = true
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
        if failsNextIndex {
            failsNextIndex = false
            log.append(.indexFailed(entities.map(\.id), priority: priority))
            throw IndexFailed()
        }
        log.append(.index(entities.map(\.id), priority: priority))
        indexed.append((entities, priority))
    }

    private func waitIfHeld(_ kind: Kind) async {
        guard holdNext == kind else { return }
        holdNext = nil
        isHolding = true
        holdingWaiters.forEach { $0.resume() }
        holdingWaiters.removeAll()
        await withCheckedContinuation { heldCall = $0 }
    }
}
