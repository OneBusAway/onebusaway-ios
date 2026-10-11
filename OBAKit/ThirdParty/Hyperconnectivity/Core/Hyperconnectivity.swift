//
//  Hyperconnectivity.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 07/05/2020.
//

import Combine
import Foundation
import Network

/// Watches the network path and, on every change, confirms Internet access by
/// fetching the configured connectivity URLs.
///
/// OBA: all mutable state is confined to `queue`, which is serial and is also the
/// queue the path monitor and every connectivity check deliver on. Upstream ran the
/// monitor on a concurrent global queue and fed each check's responses back from a
/// separate `URLSession` per URL, so the success count and `cancellable` were
/// mutated from several threads at once.
nonisolated final class Hyperconnectivity: @unchecked Sendable {

    // MARK: Type declarations
    typealias Configuration = HyperconnectivityConfiguration
    typealias ConnectivityChanged = @Sendable (ConnectivityResult) -> Void
    typealias Publisher = ConnectivityPublisher

    // MARK: State
    private let configuration: Configuration
    private let queue = DispatchQueue(label: "Hyperconnectivity", qos: .utility)

    // OBA: one session for the lifetime of the instance, invalidated in `deinit`.
    // Upstream built a new session for every URL of every check and never
    // invalidated any of them.
    private let session: URLSession

    private var checkCancellable: AnyCancellable?
    private var connectivityChanged: ConnectivityChanged?
    private var pathMonitor: NWPathMonitor?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.session = URLSession(configuration: configuration.nonCachingURLSessionConfiguration)
    }

    deinit {
        pathMonitor?.cancel()
        checkCancellable?.cancel()
        session.invalidateAndCancel()
    }

    /// Starts monitoring. `connectivityChanged` is called on a background queue
    /// once per network path change. Calling this while already started does nothing.
    func startNotifier(connectivityChanged: @escaping ConnectivityChanged) {
        queue.async { [self] in
            guard pathMonitor == nil else { return }

            self.connectivityChanged = connectivityChanged
            let pathMonitor = NWPathMonitor()
            pathMonitor.pathUpdateHandler = { [weak self] path in
                self?.pathUpdated(path)
            }
            self.pathMonitor = pathMonitor
            pathMonitor.start(queue: queue)
        }
    }

    func stopNotifier() {
        queue.async { [self] in
            // OBA: upstream dropped its reference without cancelling the monitor,
            // which kept running — and the app stops and restarts on every
            // foreground.
            pathMonitor?.cancel()
            pathMonitor = nil
            checkCancellable?.cancel()
            checkCancellable = nil
            connectivityChanged = nil
        }
    }
}

nonisolated private extension Hyperconnectivity {

    /// Invoked on `queue` on every `NWPath` change.
    func pathUpdated(_ path: NWPath) {
        dispatchPrecondition(condition: .onQueue(queue))

        checkCancellable?.cancel()

        let requests = configuration.connectivityURLRequests
        let validator = configuration.responseValidator
        let checks = requests.map { request in
            session.dataTaskPublisher(for: request)
                .map { validator.isResponseValid($0.response, data: $0.data) }
                // OBA: a request that fails is a failed check. Upstream let the
                // error end the merged stream, so one unreachable URL reported no
                // connectivity even when another URL had already succeeded.
                .replaceError(with: false)
        }

        let totalChecks = UInt(requests.count)
        let successThreshold = configuration.successThreshold
        var successfulChecks: UInt = 0
        var hasReported = false

        func report() {
            guard !hasReported else { return }
            hasReported = true
            let result = ConnectivityResult(
                path: path,
                successfulChecks: successfulChecks,
                totalChecks: totalChecks,
                successThreshold: successThreshold
            )
            connectivityChanged?(result)
        }

        checkCancellable = Publishers.MergeMany(checks)
            .receive(on: queue)
            .sink(receiveCompletion: { _ in
                report()
            }, receiveValue: { [weak self] isValid in
                if isValid {
                    successfulChecks += 1
                }
                guard Percentage(successfulChecks, outOf: totalChecks) >= successThreshold else {
                    return
                }
                // Enough checks have passed; the rest cannot change the answer.
                report()
                self?.checkCancellable?.cancel()
            })
    }
}
