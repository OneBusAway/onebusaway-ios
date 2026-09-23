//
//  StopArrivalsModel.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
import OBAKitCore

/// Drives the stop screen: a 30-second poll while the scene is active.
@MainActor
@Observable
public final class StopArrivalsModel {
    public enum Phase: Equatable {
        case loading
        case empty(updatedAt: Date)
        case failed(String)
        /// `stale` is set when a later poll failed; the list and its
        /// `updatedAt` are the last good ones.
        case loaded([ArrivalDeparture], updatedAt: Date, stale: Bool)
    }

    public let stop: Stop
    public private(set) var phase: Phase

    @ObservationIgnored private let host: WatchAppHost
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let poller = StopArrivalsPoller()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(host: WatchAppHost, stop: Stop, interval: Duration = .seconds(30)) {
        self.host = host
        self.stop = stop
        self.interval = interval
        self.phase = .loading
    }

    public func startPolling() {
        guard pollTask == nil else { return }
        guard let apiService = host.apiService else {
            phase = .failed(OBALoc("arrivals.no_service", value: "No transit region selected.", comment: "Arrivals cannot load without a region"))
            return
        }

        let stream = poller.arrivals(for: stop.id, every: interval, using: apiService, clock: ContinuousClock())
        pollTask = Task { [weak self] in
            for await result in stream {
                guard let self, !Task.isCancelled else { return }
                self.apply(result)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func retry() {
        stopPolling()
        phase = .loading
        startPolling()
    }

    private func apply(_ result: Result<[ArrivalDeparture], Error>) {
        let now = Date()
        switch result {
        case .success(let arrivals):
            phase = arrivals.isEmpty ? .empty(updatedAt: now) : .loaded(arrivals, updatedAt: now, stale: false)
        case .failure(let error):
            switch phase {
            case .loaded(let arrivals, let updatedAt, _):
                phase = .loaded(arrivals, updatedAt: updatedAt, stale: true)
            case .empty:
                break
            case .loading, .failed:
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
