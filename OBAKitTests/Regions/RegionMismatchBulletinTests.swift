//
//  RegionMismatchBulletinTests.swift
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
@testable import OBAKit
@testable import OBAKitCore

/// The card the map shows when the rider is standing in a different region from
/// the one they selected.
///
/// The rider's region comes from the location the test gives its own
/// `LocationManagerMock`, so `physicallyLocatedRegion` is the real computation.
/// The bulletin keeps its page private; the tests read it through `Mirror` and
/// call the page's button handlers, which is what tapping the buttons does.
/// Never showing the bulletin is safe: `dismissBulletin` returns early when it
/// isn't on screen.
@Suite(.serialized)
final class RegionMismatchBulletinTests: OBATestCase {

    private var queue: OperationQueue!
    private var locationManager: LocationManagerMock!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        locationManager = LocationManagerMock()
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Locations

    private var tampa: CLLocation {
        let center = Fixtures.tampaRegion.centerCoordinate
        return CLLocation(latitude: center.latitude, longitude: center.longitude)
    }

    /// The middle of the Pacific, inside no region.
    private let openOcean = CLLocation(latitude: 0, longitude: -150)

    // MARK: - Helpers

    /// An `Application` whose selected region is Puget Sound, or none, with
    /// automatic region selection off. `fixedRegionName` does both for Puget Sound.
    private func buildApplication(selectingPugetSound: Bool = true) -> Application {
        if !selectingPugetSound {
            userDefaults.set(false, forKey: RegionsService.automaticallySelectRegionUserDefaultsKey)
        }
        let loader = MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        // Switching region refreshes agencies from the new region's server, so match on path, not host.
        loader.mock(data: Fixtures.loadData(file: "agencies_with_coverage.json")) { request in
            request.url?.path.hasSuffix("/api/where/agencies-with-coverage.json") ?? false
        }
        // Moving the map can load stops and probe for on-demand zones in the new area.
        loader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }
        Fixtures.stubOnDemandViewportProbe(dataLoader: loader)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: LocationService(userDefaults: userDefaults, locationManager: locationManager),
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: loader,
            fixedRegionName: selectingPugetSound ? Fixtures.pugetSoundRegion.name : nil
        )
        return Application(config: config)
    }

    private func page(of bulletin: RegionMismatchBulletin) throws -> ThemedBulletinPage {
        try #require(Mirror(reflecting: bulletin).descendant("page") as? ThemedBulletinPage)
    }

    // MARK: - When it appears

    @Test func `No card without a selected region`() throws {
        let application = buildApplication(selectingPugetSound: false)
        locationManager.location = tampa

        #expect(application.regionsService.currentRegion == nil)
        #expect(application.regionsService.physicallyLocatedRegion?.name == "Tampa Bay")
        #expect(RegionMismatchBulletin(application: application) == nil)
    }

    @Test func `No card when the rider is in no region`() throws {
        let application = buildApplication()
        locationManager.location = openOcean

        #expect(application.regionsService.currentRegion?.name == "Puget Sound")
        #expect(application.regionsService.physicallyLocatedRegion == nil)
        #expect(RegionMismatchBulletin(application: application) == nil)
    }

    // MARK: - Text

    @Test func `The card names the selected region first, then the rider's, and each button names its region`() throws {
        let application = buildApplication()
        locationManager.location = tampa

        let bulletin = try #require(RegionMismatchBulletin(application: application))
        let page = try page(of: bulletin)

        let body = try #require(page.descriptionText)
        let selected = try #require(body.range(of: "Puget Sound"))
        let physical = try #require(body.range(of: "Tampa Bay"))
        #expect(selected.lowerBound < physical.lowerBound)

        let change = try #require(page.actionButtonTitle)
        #expect(change.contains("Tampa Bay"))
        #expect(!change.contains("Puget Sound"))

        let showOnMap = try #require(page.alternativeButtonTitle)
        #expect(showOnMap.contains("Puget Sound"))
        #expect(!showOnMap.contains("Tampa Bay"))
    }

    // MARK: - Buttons

    @Test func `Change switches to the rider's region, turns automatic selection back on, and reports the change`() throws {
        let application = buildApplication()
        locationManager.location = tampa
        #expect(!application.regionsService.automaticallySelectRegion)

        var changed = 0
        var shownOnMap = 0
        let bulletin = try #require(RegionMismatchBulletin(
            application: application,
            onChangedPhysicalRegion: { changed += 1 },
            onShowSelectedRegionOnMap: { shownOnMap += 1 }
        ))
        let page = try page(of: bulletin)

        // Leave every region before tapping, so turning automatic selection on
        // can't pick Tampa Bay by itself: only the button's own switch can.
        locationManager.location = openOcean

        withExtendedLifetime(bulletin) {
            page.actionHandler?(page)
        }

        #expect(application.regionsService.currentRegion?.name == "Tampa Bay")
        #expect(application.regionsService.automaticallySelectRegion)
        #expect(changed == 1)
        #expect(shownOnMap == 0)
    }

    @Test func `Show on map hands back to the caller and keeps the selected region`() throws {
        let application = buildApplication()
        locationManager.location = tampa

        var changed = 0
        var shownOnMap = 0
        let bulletin = try #require(RegionMismatchBulletin(
            application: application,
            onChangedPhysicalRegion: { changed += 1 },
            onShowSelectedRegionOnMap: { shownOnMap += 1 }
        ))
        let page = try page(of: bulletin)

        withExtendedLifetime(bulletin) {
            page.alternativeHandler?(page)
        }

        #expect(shownOnMap == 1)
        #expect(changed == 0)
        #expect(application.regionsService.currentRegion?.name == "Puget Sound")
        #expect(!application.regionsService.automaticallySelectRegion)
    }

    @Test func `Without a map callback, Show on map moves the map to the selected region`() throws {
        let application = buildApplication()
        locationManager.location = tampa
        let pugetSound = try #require(application.regionsService.currentRegion)
        let tampaBay = try #require(application.regionsService.physicallyLocatedRegion)

        let mapView = application.mapRegionManager.mapView
        mapView.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        mapView.visibleMapRect = tampaBay.serviceRect
        #expect(!pugetSound.serviceRect.contains(MKMapPoint(mapView.centerCoordinate)))

        let bulletin = try #require(RegionMismatchBulletin(application: application))
        let page = try page(of: bulletin)

        withExtendedLifetime(bulletin) {
            page.alternativeHandler?(page)
        }

        #expect(pugetSound.serviceRect.contains(MKMapPoint(mapView.centerCoordinate)))
        #expect(application.regionsService.currentRegion?.name == "Puget Sound")
    }
}
