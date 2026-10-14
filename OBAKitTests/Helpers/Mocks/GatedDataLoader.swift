//
//  GatedDataLoader.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Wraps a `MockDataLoader` and holds a request open until the test lets it go, so
/// state that exists only *while* a request is in flight — a row's loading id, an
/// in-progress flag — can be observed rather than inferred from what's left behind
/// afterwards.
///
/// `CountingDataLoader` yields once so concurrent tasks interleave; this one blocks
/// until told otherwise, which is what an assertion made mid-request needs to be
/// deterministic rather than a race against a mock that answers instantly.
// @unchecked Sendable: all mutable state is guarded by `lock`.
// `nonisolated` for the same reason `MockDataLoader` is: `data(for:)` runs on
// whatever task issued the request, not on the test target's default main actor.
nonisolated final class GatedDataLoader: NSObject, URLDataLoader, @unchecked Sendable {

    private let inner: MockDataLoader
    /// Which requests the gate holds; the rest pass straight through, so a test can
    /// hold one endpoint open while the app's other traffic keeps flowing.
    private let isGated: @Sendable (URLRequest) -> Bool
    /// Whether a gated request fetches its response before the hold rather than
    /// after, so a caller cancelled mid-hold still gets the answer — the network
    /// replied, and the caller has to notice the cancellation for itself.
    private let holdsAfterResponse: Bool
    private let lock = NSLock()

    private var hasArrived = false
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(
        _ inner: MockDataLoader,
        gating isGated: @escaping @Sendable (URLRequest) -> Bool = { _ in true },
        holdsAfterResponse: Bool = false
    ) {
        self.inner = inner
        self.isGated = isGated
        self.holdsAfterResponse = holdsAfterResponse
    }

    /// Suspends until a request reaches the loader — i.e. until the code under test
    /// has run everything it does before awaiting the network.
    func waitForRequest() async {
        await withCheckedContinuation { continuation in
            let alreadyArrived = lock.withLock { () -> Bool in
                if hasArrived { return true }
                arrivalContinuation = continuation
                return false
            }
            // Resumed outside the lock: `resume()` can run the waiter inline, and a
            // waiter that comes straight back here would deadlock on a held lock.
            if alreadyArrived { continuation.resume() }
        }
    }

    /// Lets the held request run to completion.
    func releaseRequest() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isReleased = true
            defer { releaseContinuation = nil }
            return releaseContinuation
        }
        continuation?.resume()
    }

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        inner.dataTask(with: request, completionHandler: completionHandler)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard isGated(request) else {
            // `MockDataLoader` answers without suspending, so without this a chain
            // of passed-through requests would run start to finish without ever
            // letting other tasks on the caller's actor in — unlike a real network.
            await Task.yield()
            return try await inner.data(for: request)
        }

        let earlyResponse = holdsAfterResponse ? try await inner.data(for: request) : nil

        let arrival = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            hasArrived = true
            defer { arrivalContinuation = nil }
            return arrivalContinuation
        }
        arrival?.resume()

        await withCheckedContinuation { continuation in
            let alreadyReleased = lock.withLock { () -> Bool in
                if isReleased { return true }
                releaseContinuation = continuation
                return false
            }
            if alreadyReleased { continuation.resume() }
        }

        if let earlyResponse { return earlyResponse }
        return try await inner.data(for: request)
    }
}
