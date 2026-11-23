//
//  LocationService+AsyncStream.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

extension LocationService {

    /// Creates and returns an `AsyncStream<CLLocation>` with automatic start/stop tracking
    /// tied to the stream consumer's lifecycle.
    ///
    /// - Parameter bufferingPolicy: The buffering policy for the stream. Defaults to `.bufferingNewest(1)`.
    /// - Returns: An `AsyncStream<CLLocation>` yielding updates as they arrive.
    public func locationStream(
        bufferingPolicy: AsyncStream<CLLocation>.Continuation.BufferingPolicy = .bufferingNewest(1)
    ) -> AsyncStream<CLLocation> {
        let (stream, continuation) = AsyncStream<CLLocation>.makeStream(bufferingPolicy: bufferingPolicy)
        let subscriptionID = UUID()

        addLocationStreamSubscriber(id: subscriptionID, continuation: continuation)

        continuation.onTermination = { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.removeLocationStreamSubscriber(id: subscriptionID)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.removeLocationStreamSubscriber(id: subscriptionID)
                }
            }
        }

        return stream
    }
}
