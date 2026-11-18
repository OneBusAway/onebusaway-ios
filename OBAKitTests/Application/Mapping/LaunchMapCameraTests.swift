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
        let last = TestData.seattleMapRect
        #expect(last.intersects(pugetSound.serviceRect))
        #expect(!MKMapRectEqualToRect(last, pugetSound.serviceRect))

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
        #expect(!MKMapRectEqualToRect(rect, pugetSound.serviceRect))
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

    // MARK: - Changing region

    /// The rider picked another region. The old viewport is in the old city, so
    /// it never wins, and nobody needs telling the region doesn't match.
    @Test func `A region change frames the new region's service rect`() {
        let rect = LaunchMapCamera.regionChangeTarget(region: pugetSound, userLocation: TestData.mockTampaLocation)
        #expect(rect.map { MKMapRectEqualToRect($0, pugetSound.serviceRect) } == true)

        #expect(LaunchMapCamera.regionChangeTarget(region: pugetSound, userLocation: nil) != nil)
    }

    @Test func `A region change to the region the rider is in zooms to the rider`() {
        #expect(LaunchMapCamera.regionChangeTarget(region: pugetSound, userLocation: TestData.mockSeattleLocation) == nil)
    }

    // MARK: - Boundary and Malformed Input Validation

    // MARK: Coordinate Validation

    @Test func `Valid coordinates pass validation`() {
        #expect(LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: 0)))
        #expect(LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 90, longitude: 180)))
        #expect(LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: -90, longitude: -180)))
        #expect(LaunchMapCamera.isValidCoordinate(TestData.seattleCoordinate))
        #expect(LaunchMapCamera.isValidLocation(TestData.mockSeattleLocation))
    }

    @Test func `Missing location fails validation`() {
        #expect(!LaunchMapCamera.isValidLocation(nil))
    }

    @Test func `Out-of-range coordinates fail validation`() {
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 90.0001, longitude: 0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: -90.0001, longitude: 0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 100.0, longitude: 0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: -100.0, longitude: 0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: 180.0001)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: -180.0001)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: 200.0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: -200.0)))
        #expect(!LaunchMapCamera.isValidLocation(CLLocation(latitude: 100.0, longitude: 0)))
    }

    @Test func `Malformed NaN and infinite coordinates fail validation`() {
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: .nan, longitude: 0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: .nan)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: .infinity, longitude: 0)))
        #expect(!LaunchMapCamera.isValidCoordinate(CLLocationCoordinate2D(latitude: 0, longitude: -.infinity)))
        #expect(!LaunchMapCamera.isValidLocation(CLLocation(latitude: .nan, longitude: 0)))
        #expect(!LaunchMapCamera.isValidLocation(CLLocation(latitude: 0, longitude: .infinity)))
    }

    // MARK: MapRect Validation

    @Test func `Valid map rect passes validation`() {
        #expect(LaunchMapCamera.isValidMapRect(TestData.seattleMapRect))
        #expect(LaunchMapCamera.isValidMapRect(pugetSound.serviceRect))
    }

    @Test func `Viewports extending beyond world edges pass validation`() {
        // MapKit allows visibleMapRect to extend past world edges when panned
        // across the 180th meridian or zoomed far out.
        let spanningMeridian = MKMapRect(x: MKMapRect.world.maxX - 10, y: 0, width: 100, height: 100)
        #expect(LaunchMapCamera.isValidMapRect(spanningMeridian))

        let negativeOrigin = MKMapRect(x: -10, y: -10, width: 100, height: 100)
        #expect(LaunchMapCamera.isValidMapRect(negativeOrigin))
    }

    @Test func `Null, empty, and negative dimension map rects fail validation`() {
        #expect(!LaunchMapCamera.isValidMapRect(.null))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 100, y: 100, width: 0, height: 100)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 100, y: 100, width: 100, height: 0)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 100, y: 100, width: -10, height: 100)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 100, y: 100, width: 100, height: -10)))
    }

    @Test func `Malformed NaN and infinite map rects fail validation`() {
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: .nan, y: 0, width: 100, height: 100)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 0, y: .nan, width: 100, height: 100)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 0, y: 0, width: .nan, height: 100)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 0, y: 0, width: 100, height: .nan)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 0, y: 0, width: .infinity, height: 100)))
        #expect(!LaunchMapCamera.isValidMapRect(MKMapRect(x: 0, y: 0, width: 100, height: .infinity)))
    }

    // MARK: Region Validation and Safe Fallback

    @Test func `Region validation and safe fallback handle missing and malformed region`() {
        #expect(LaunchMapCamera.isValidRegion(pugetSound))
        #expect(!LaunchMapCamera.isValidRegion(nil))
        #expect(MKMapRectEqualToRect(LaunchMapCamera.safeServiceRect(for: nil), MKMapRect.world))

        // Malformed region with empty zero-delta coordinate span
        let emptySpan = MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        let emptyCoordRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), span: emptySpan)
        let malformedRegion = Region(
            name: "Malformed",
            OBABaseURL: URL(string: "https://example.com")!,
            coordinateRegion: emptyCoordRegion,
            contactEmail: "test@example.com"
        )
        #expect(!LaunchMapCamera.isValidRegion(malformedRegion))
        #expect(MKMapRectEqualToRect(LaunchMapCamera.safeServiceRect(for: malformedRegion), MKMapRect.world))
    }

    // MARK: Target calculation fails safely on malformed input

    @Test func `Malformed user location fails safely in target calculation`() {
        let malformedLocation = CLLocation(latitude: 100.0, longitude: 0)
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: malformedLocation,
            lastVisibleMapRect: nil
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(!showMismatch)
    }

    @Test func `Malformed lastVisibleMapRect fails safely in target calculation`() {
        let malformedRect = MKMapRect.null
        let target = LaunchMapCamera.target(
            selectedRegion: pugetSound,
            userLocation: nil,
            lastVisibleMapRect: malformedRect
        )
        guard case .mapRect(let rect, let showMismatch) = target else {
            Issue.record("expected mapRect, got \(target)")
            return
        }
        #expect(MKMapRectEqualToRect(rect, pugetSound.serviceRect))
        #expect(!showMismatch)
    }

    @Test func `Malformed user location fails safely in regionChangeTarget`() {
        let malformedLocation = CLLocation(latitude: .nan, longitude: 0)
        let rect = LaunchMapCamera.regionChangeTarget(region: pugetSound, userLocation: malformedLocation)
        #expect(rect.map { MKMapRectEqualToRect($0, pugetSound.serviceRect) } == true)
    }
}
