//
//  MapViewportRecorderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The SwiftUI panel's only writer of `MapRegionManager.lastVisibleMapRect`.
@Suite(.serialized)
final class MapViewportRecorderTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test @MainActor
    func `Record persists the rect as the last visible map rect`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let recorder = MapViewportRecorder(application: application)
        let rect = MKMapRect(
            origin: MKMapPoint(x: 42_000_000, y: 91_000_000),
            size: MKMapSize(width: 250_000, height: 180_000)
        )

        recorder.record(rect)

        let stored = try #require(application.mapRegionManager.lastVisibleMapRect)
        #expect(stored.origin.x == rect.origin.x)
        #expect(stored.origin.y == rect.origin.y)
        #expect(stored.size.width == rect.size.width)
        #expect(stored.size.height == rect.size.height)
    }

    @Test @MainActor
    func `Record overwrites a previously stored rect`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let recorder = MapViewportRecorder(application: application)
        let first = MKMapRect(origin: MKMapPoint(x: 1, y: 2), size: MKMapSize(width: 3, height: 4))
        let second = MKMapRect(origin: MKMapPoint(x: 10, y: 20), size: MKMapSize(width: 30, height: 40))

        recorder.record(first)
        recorder.record(second)

        let stored = try #require(application.mapRegionManager.lastVisibleMapRect)
        #expect(stored.origin.x == second.origin.x)
        #expect(stored.size.width == second.size.width)
    }
}
