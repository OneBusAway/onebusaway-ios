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
/// Each request cancels the one before it, whether it is still waiting or
/// already syncing, so after a region switch nothing more is written for the old
/// region. `Mutex` keeps the class `Sendable`, so `deinit` can cancel too.
public final class RegionStopSyncScheduler: Sendable {
    private let service: RegionStopSyncService
    private let delay: Duration
    private let pending = Mutex<Task<Void, Never>?>(nil)

    public init(service: RegionStopSyncService, delay: Duration = .seconds(5)) {
        self.service = service
        self.delay = delay
    }

    deinit {
        pending.withLock { $0?.cancel() }
    }

    /// The request in flight, if any. Internal so tests can await it.
    var pendingSync: Task<Void, Never>? {
        pending.withLock { $0 }
    }

    /// Syncs `regionID` through `fetcher` after the pause, replacing any earlier
    /// request.
    public func schedule(regionID: Int, using fetcher: any StopsForAgencyFetching) {
        let service = service
        let delay = delay
        pending.withLock { task in
            task?.cancel()
            task = Task.detached(priority: .utility) {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                await service.sync(regionID: regionID, using: fetcher)
            }
        }
    }
}
