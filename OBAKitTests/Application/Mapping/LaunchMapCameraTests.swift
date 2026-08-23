//
//  LaunchMapCameraTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKitCore

/// Launch camera for #615. A rider in Tampa with Puget Sound selected must
/// open on Puget Sound, not GPS. The locate button is a separate path.
@Suite(.serialized)
struct LaunchMapCameraTests {

    private var pugetSound: Region { Fixtures.pugetSoundRegion }

    @Test func `GPS inside the selected region zooms to the user`() {
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: TestData.mockSeattleLocation,
            lastVisibleMapRect: nil
        )
        guard case .userLocation = target else {
            Issue.record("expected userLocation, got \(target)")
            return
        }
    }

    @Test func `GPS outside the selected region frames the region's service rect`() {
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: TestData.mockTampaLocation,
            lastVisibleMapRect: nil
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(showMismatch)
    }

    @Test func `GPS outside prefers a last viewport that still sits in the region`() {
        let last = pugetSound.serviceRect
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: TestData.mockTampaLocation,
            lastVisibleMapRect: last
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, last))
        #expect(showMismatch)
    }

    @Test func `GPS outside ignores a last viewport that is also outside the region`() {
        let tampaViewport = Fixtures.tampaRegion.serviceRect
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: TestData.mockTampaLocation,
            lastVisibleMapRect: tampaViewport
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(showMismatch)
    }

    @Test func `No GPS restores the last viewport`() {
        let last = TestData.seattleMapRect
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: nil,
            lastVisibleMapRect: last
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, last))
        #expect(!showMismatch)
    }

    @Test func `No GPS and no last viewport frames the region's service rect`() {
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: nil,
            lastVisibleMapRect: nil
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(!showMismatch)
    }
}
