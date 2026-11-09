//
//  SpeedProviderMocks.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit

/// Returns a fixed speed, or throws on authorization.
struct FakeSpeedProvider: SpeedProviding {
    var isAvailable: Bool = true
    var authorizationError: Error?
    var sampleSpeed: Double?

    func requestAuthorization() async throws {
        if let authorizationError {
            throw authorizationError
        }
    }

    func fetchSpeed() async -> Double? {
        sampleSpeed
    }
}

/// Records authorization requests so a test can assert that merely opening Settings makes none.
final class SpySpeedProvider: SpeedProviding {
    var isAvailable = true
    var sampleSpeed: Double?
    private(set) var requestAuthorizationCount = 0

    func requestAuthorization() async throws {
        requestAuthorizationCount += 1
    }

    func fetchSpeed() async -> Double? {
        sampleSpeed
    }
}

/// Defers the speed until the test releases it, so an opt-out can race a sync in flight.
actor SpeedFetchGate {
    private var continuation: CheckedContinuation<Double?, Never>?
    private var fetchingContinuation: CheckedContinuation<Void, Never>?

    func wait() async -> Double? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            // Signal arrival: a test awaiting `waitUntilFetching()` now proceeds.
            self.fetchingContinuation?.resume()
            self.fetchingContinuation = nil
        }
    }

    /// Returns only after `wait()` has stored its continuation, so the test knows
    /// the sync is parked in the fetch (and not still before it) before cancelling.
    func waitUntilFetching() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            self.fetchingContinuation = continuation
        }
    }

    func resume(returning value: Double?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// Parks `fetchSpeed()` on a `SpeedFetchGate`.
struct GatedSpeedProvider: SpeedProviding {
    var isAvailable: Bool = true
    let gate: SpeedFetchGate

    func requestAuthorization() async throws {}

    func fetchSpeed() async -> Double? {
        await gate.wait()
    }
}

extension SpeedSyncConfiguration {
    /// One provider for both speeds, with empty copy.
    static func stub(_ provider: any SpeedProviding) -> SpeedSyncConfiguration {
        SpeedSyncConfiguration(
            walkingProvider: provider,
            bikeProvider: provider,
            text: SpeedSyncText(toggleTitle: "", walkingFooter: "", walkingFailureMessage: "", bikeFooter: "", bikeFailureMessage: "")
        )
    }
}
