//
//  OnDemandLocalityResolver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// Spec 2.8 Locality: the reverse-geocoded locality of a point when it
/// arrives within a second; otherwise nil and the copy falls back.
struct OnDemandLocalityResolver {
    static let timeout: TimeInterval = 1

    private let geocode: @Sendable (CLLocation) async -> String?

    /// `geocode` is injectable so tests can stand in for the network.
    init(geocode: @escaping @Sendable (CLLocation) async -> String? = Self.reverseGeocodedLocality) {
        self.geocode = geocode
    }

    /// Returns after at most `timeout` even when the lookup never finishes:
    /// the lookup and the timer race as unstructured tasks, so the answer
    /// never waits on a lookup that ignores cancellation (a task group
    /// would await every child). The loser is cancelled.
    func locality(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocode = self.geocode
        return await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            let lookup = Task {
                answer.resume(with: await geocode(location))
            }
            Task {
                try? await Task.sleep(for: .seconds(Self.timeout))
                answer.resume(with: nil)
                lookup.cancel()
            }
        }
    }

    /// `CLGeocoder` ignores Swift task cancellation, so a cancelled lookup
    /// calls `cancelGeocode()`, which completes the request with
    /// `kCLErrorGeocodeCanceled` instead of leaving it in flight.
    @Sendable static func reverseGeocodedLocality(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        return await withTaskCancellationHandler {
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            return placemarks?.first?.locality
        } onCancel: {
            geocoder.cancelGeocode()
        }
    }
}

/// Resumes a continuation with the first answer only.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(with locality: String?) {
        let pending = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: locality)
    }
}
