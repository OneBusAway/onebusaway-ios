//
//  StopArrivalsModel.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation

/// Drives the stop screen: a 30-second poll while the scene is active.
@MainActor
@Observable
public final class StopArrivalsModel {
    public enum Phase: Equatable {
        case loading
        case empty(updatedAt: Date)
        case offline
        case failed(String)
        /// `stale` is set when a later poll failed; the list and its
        /// `updatedAt` are the last good ones.
        case loaded([ArrivalDeparture], updatedAt: Date, stale: Bool)
    }

    public typealias APIServiceProvider = @MainActor () -> RESTAPIService?

    public let stop: Stop
    public private(set) var phase: Phase

    @ObservationIgnored private let apiServiceProvider: APIServiceProvider
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let poller: StopArrivalsPoller
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Continuations for the streams forwarded to the running poller. These
    /// are created fresh on every startPolling(): an AsyncStream whose
    /// iteration was cancelled cannot be iterated again, so a stream must
    /// never be reused across a retry() — the poller bridges them internally
    /// and never finishes them, but its cancellation still ends their
    /// iteration. `.bufferingNewest(1)` keeps only the latest phase /
    /// coalesces repeated refreshes into one.
    @ObservationIgnored private var scenePhaseContinuation: AsyncStream<PollerScenePhase>.Continuation?
    @ObservationIgnored private var refreshContinuation: AsyncStream<Void>.Continuation?
    /// Latest scene phase, replayed into a fresh stream when polling starts
    /// so a poll started while backgrounded begins paused.
    @ObservationIgnored private var currentPhase: PollerScenePhase = .active

    public init(
        stop: Stop,
        apiServiceProvider: @escaping APIServiceProvider,
        interval: Duration = .seconds(30),
        poller: StopArrivalsPoller = StopArrivalsPoller()
    ) {
        self.stop = stop
        self.apiServiceProvider = apiServiceProvider
        self.interval = interval
        self.poller = poller
        self.phase = .loading
    }

    public convenience init(
        stop: Stop,
        apiService: RESTAPIService?,
        interval: Duration = .seconds(30),
        poller: StopArrivalsPoller = StopArrivalsPoller()
    ) {
        self.init(stop: stop, apiServiceProvider: { apiService }, interval: interval, poller: poller)
    }

    public func startPolling() {
        guard pollTask == nil else { return }
        guard let apiService = apiServiceProvider() else {
            phase = .failed(Strings.noTransitRegion)
            return
        }

        // Fresh streams per poll: a stream whose iteration was cancelled
        // cannot be iterated again, so these must not be reused across a
        // retry(). The current phase is replayed first so a poll started
        // while backgrounded begins paused.
        let (scenePhaseStream, scenePhaseContinuation) = AsyncStream<PollerScenePhase>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.scenePhaseContinuation = scenePhaseContinuation
        let (refreshStream, refreshContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.refreshContinuation = refreshContinuation
        scenePhaseContinuation.yield(currentPhase)

        let stream = poller.arrivals(for: stop.id, every: interval, using: apiService, clock: ContinuousClock(), scenePhaseStream: scenePhaseStream, refreshSignal: refreshStream, initialScenePhase: currentPhase)
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
        // The streams die with the cancelled poller; fresh ones are created
        // on the next startPolling().
        scenePhaseContinuation = nil
        refreshContinuation = nil
    }

    public func retry() {
        // Refresh in place when already polling instead of restarting the
        // poll: the refresh signal triggers an immediate fetch.
        if pollTask != nil {
            phase = .loading
            triggerRefresh()
        } else {
            phase = .loading
            startPolling()
        }
    }

    /// Forwards a scene phase change to the poller so it can pause in the
    /// background and resume with an immediate fetch on foregrounding. The
    /// phase is remembered so a later poll starts with the right one.
    public func setScenePhase(_ phase: PollerScenePhase) {
        currentPhase = phase
        scenePhaseContinuation?.yield(phase)
    }

    /// Triggers an immediate fetch on the running poller (pull-to-refresh /
    /// Retry), without waiting for the timer and without restarting the poll.
    /// No-op when not polling.
    public func triggerRefresh() {
        refreshContinuation?.yield()
    }

    func apply(_ result: Result<[ArrivalDeparture], Error>) {
        let now = Date()
        switch result {
        case .success(let arrivals):
            phase = arrivals.isEmpty ? .empty(updatedAt: now) : .loaded(arrivals, updatedAt: now, stale: false)
        case .failure(let error):
            switch phase {
            case .loaded(let arrivals, let updatedAt, _):
                phase = .loaded(arrivals, updatedAt: updatedAt, stale: true)
            case .empty:
                if ErrorClassifier.category(for: error) == .offline {
                    phase = .offline
                }
            case .loading, .failed, .offline:
                if ErrorClassifier.category(for: error) == .offline {
                    phase = .offline
                } else {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }
}
