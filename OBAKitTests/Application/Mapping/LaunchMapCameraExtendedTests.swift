//
//  LaunchMapCameraExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import OBAKitCore

/// Tests for `LaunchMapCamera` camera framing target decisions when user location
/// is unavailable, region boundaries change, or last viewports are out of date.
@Suite(.serialized)
struct LaunchMapCameraExtendedTests {

    private var pugetSound: Region { Fixtures.pugetSoundRegion }

    // MARK: - Nil User Location Decisions

    @Test func `Nil user location with no last visible map rect frames region serviceRect without mismatch`() {
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: nil,
            lastVisibleMapRect: nil
        )

        guard case let .mapRect(rect, showMismatch) = target else {
            Issue.record("Expected mapRect target, got \(target)")
            return
        }

        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(!showMismatch) // No mismatch alert when GPS simply hasn't fired yet
    }

    @Test func `Nil user location uses last visible rect if inside serviceRect`() {
        let lastRect = TestData.seattleMapRect

        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: nil,
            lastVisibleMapRect: lastRect
        )

        guard case let .mapRect(rect, showMismatch) = target else {
            Issue.record("Expected mapRect target, got \(target)")
            return
        }

        #expect(MKMapRectEqualToRect(rect, lastRect))
        #expect(!showMismatch)
    }

    @Test func `Disjoint last visible rect is discarded in favor of region serviceRect`() {
        // Tampa map rect has no overlap with Puget Sound
        let tampaCoord = CLLocationCoordinate2D(latitude: 27.9506, longitude: -82.4572)
        let tampaPoint = MKMapPoint(tampaCoord)
        let tampaRect = MKMapRect(x: tampaPoint.x - 1000, y: tampaPoint.y - 1000, width: 2000, height: 2000)

        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: nil,
            lastVisibleMapRect: tampaRect
        )

        guard case let .mapRect(rect, showMismatch) = target else {
            Issue.record("Expected mapRect target, got \(target)")
            return
        }

        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(!showMismatch)
    }
}
