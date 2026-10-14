//
//  StopOnDemandServicesLoader.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Loads the on-demand services a stop references (`Stop.onDemandServiceIDs`)
/// for the stop page's on-demand card, once per distinct pointer set.
///
/// The result goes to `onLoad`: empty for non-flex stops and when every service
/// failed to load. Failures never surface as an error — the departures list is
/// the page, and this card is an addition to it.
final class StopOnDemandServicesLoader {
    private let onLoad: ([OnDemandService]) -> Void

    /// The in-flight load; held for cancellation and so tests can await it.
    private(set) var task: Task<Void, Never>?

    /// The pointer set the current or last load was started for — recorded at the
    /// start so refreshes landing mid-load (auto-extension fires several) don't
    /// restart it. Nil after a load that produced nothing, so the next refresh retries.
    private var requestedIDs: [String]?

    init(onLoad: @escaping ([OnDemandService]) -> Void) {
        self.onLoad = onLoad
    }

    isolated deinit {
        task?.cancel()
    }

    /// Loads the services behind `stop.onDemandServiceIDs` when the set changes,
    /// cancelling a load still running for the previous set so its result never lands.
    func refresh(for stop: Stop, apiService: RESTAPIService?) {
        let ids = stop.onDemandServiceIDs
        guard ids != requestedIDs else { return }

        task?.cancel()
        task = nil
        requestedIDs = ids

        guard !ids.isEmpty, let apiService else {
            onLoad([])
            return
        }

        task = Task { [weak self] in
            // Simplified geometry: the service page this row opens draws the zones.
            let loaded = await apiService.loadOnDemandServices(ids: ids, geometryDetail: .simplified)
            // The task's flag, not an error: a `URLError.cancelled` this task
            // didn't ask for is an ordinary failure that must still allow a retry.
            guard !Task.isCancelled, let self else { return }
            self.onLoad(loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            if loaded.isEmpty {
                self.requestedIDs = nil
            }
        }
    }

    /// Drops the card and forgets its pointer set, so a later refresh reloads it.
    func clear() {
        task?.cancel()
        task = nil
        requestedIDs = nil
        onLoad([])
    }
}
