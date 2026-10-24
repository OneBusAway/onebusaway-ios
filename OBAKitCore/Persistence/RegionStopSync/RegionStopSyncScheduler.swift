//
//  RegionStopSyncScheduler.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization

/// Runs `RegionStopSyncService` after a short pause, so a launch, its first
/// activation and a region change in quick succession make one sync, not three.
///
/// A request for the region whose sync is already waiting or running leaves
/// that sync alone: activation fires whenever a system alert or Control Center
/// is dismissed, and restarting would throw away a slow sync's progress. A
/// request for another region cancels it, so after a region switch nothing more
/// is written for the old region. `Mutex` keeps the class `Sendable`, so
/// `deinit` can cancel too.
final class RegionStopSyncScheduler: Sendable {
    private struct Pending {
        let regionID: Int
        let id: UInt64
        let task: Task<Void, Never>
    }

    private struct State {
        var nextID: UInt64 = 0
        var pending: Pending?
    }

    private let service: RegionStopSyncService
    private let delay: Duration
    private let state = Mutex(State())

    init(service: RegionStopSyncService, delay: Duration = .seconds(5)) {
        self.service = service
        self.delay = delay
    }

    deinit {
        state.withLock { $0.pending?.task.cancel() }
    }

    /// The sync waiting or running, if any. Internal so tests can await it.
    var pendingSync: Task<Void, Never>? {
        state.withLock { $0.pending?.task }
    }

    /// Syncs `regionID` through `fetcher` after the pause, unless a sync for
    /// `regionID` is already waiting or running.
    func schedule(regionID: Int, using fetcher: any StopsForAgencyFetching) {
        let service = service
        let delay = delay
        state.withLock { state in
            if state.pending?.regionID == regionID {
                return
            }
            state.pending?.task.cancel()

            let id = state.nextID
            state.nextID += 1
            let task = Task.detached(priority: .utility) { [weak self] in
                defer { self?.finish(id) }
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                await service.sync(regionID: regionID, using: fetcher)
            }
            state.pending = Pending(regionID: regionID, id: id, task: task)
        }
    }

    /// Forgets the sync `id` once it ends, unless a newer one replaced it.
    private func finish(_ id: UInt64) {
        state.withLock { state in
            if state.pending?.id == id {
                state.pending = nil
            }
        }
    }
}
