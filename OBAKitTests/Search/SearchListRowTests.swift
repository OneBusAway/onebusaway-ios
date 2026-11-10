//
//  SearchListRowTests.swift
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

/// Row identity and the subtitle and icon helpers behind the search list's rows.
/// `SearchResultRowTests` covers the disambiguation sheet's mapping onto these rows.
@Suite(.serialized)
final class SearchListRowTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// An application whose location service has a fix at `TestData.seattleCoordinate`,
    /// with distances formatted for `en_US` so the expected strings don't depend on
    /// the machine's locale.
    private func applicationWithFix() throws -> Application {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let application = buildApplication(queue: queue, dataLoader: loader)
        application.formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        application.locationService.startUpdatingLocation()
        try #require(application.locationService.currentLocation != nil)
        return application
    }

    /// An application with no location fix: the location manager isn't authorized.
    private func applicationWithoutFix() throws -> Application {
        let loader = MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: loader, onDemandSupport: OnDemandSupport())
        let application = Application(config: config)
        try #require(application.locationService.currentLocation == nil)
        return application
    }

    /// A stop 0.01° of latitude (about 1.1 km) north of `TestData.seattleCoordinate`.
    private func stop(direction: String?) throws -> Stop {
        var dictionary: [String: Any] = [
            "code": "75403",
            "id": "1_75403",
            "lat": TestData.seattleCoordinate.latitude + 0.01,
            "lon": TestData.seattleCoordinate.longitude,
            "locationType": 0,
            "name": "Broadway & E Pike St",
            "routeIds": []
        ]
        dictionary["direction"] = direction
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dictionary)
    }

    private func place(latitude: Double, longitude: Double) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    }

    /// A map item at the same spot as `stop(direction:)`. `subtitleForMapItem` reads
    /// `MKMapItem.address` from iOS 26 on, so the tests that use this need iOS 26.
    @available(iOS 26.0, *)
    private func mapItem(shortAddress: String?) -> MKMapItem {
        let location = CLLocation(latitude: TestData.seattleCoordinate.latitude + 0.01, longitude: TestData.seattleCoordinate.longitude)
        let address = shortAddress.flatMap { MKAddress(fullAddress: "\($0), Seattle, WA 98122", shortAddress: $0) }
        return MKMapItem(location: location, address: address)
    }

    private func systemName(_ icon: SearchListRow.Icon) -> String? {
        if case .system(let name) = icon { return name }
        return nil
    }

    // MARK: - Row identity

    /// A recent stop, a bookmark and a disambiguation result can all name the same
    /// stop, and the list renders them through one `ForEach`.
    @Test
    func `Rows of different kinds never share an id, even for the same stop and title`() {
        let place = place(latitude: 47.6, longitude: -122.3)
        let kinds: [SearchListRow.Kind] = [
            .quickSearch(.stopNumber),
            .recentStop(id: "1_75403"),
            .bookmark(id: "1_75403"),
            .placemark(place),
            .searchResult(id: "1_75403"),
            .clearRecents,
            .loading,
            .noResults,
            .error("Offline", systemImage: "wifi.slash")
        ]

        let ids = kinds.map { SearchListRow(kind: $0, title: "Broadway").id }

        #expect(ids == [
            // `SearchType.stopNumber.rawValue` is 2.
            "quickSearch-2-Broadway",
            "recentStop-1_75403-Broadway",
            "bookmark-1_75403-Broadway",
            "placemark-47.6--122.3-Broadway",
            "searchResult-1_75403-Broadway",
            "clearRecents-Broadway",
            "loading-Broadway",
            "noResults-Broadway",
            "error-Offline-Broadway"
        ])
    }

    @Test
    func `Two places with the same name at different spots get distinct ids`() {
        let north = place(latitude: 47.62, longitude: -122.32)
        let south = place(latitude: 47.60, longitude: -122.32)

        let northRow = SearchListRow(kind: .placemark(north), title: "Starbucks")
        let southRow = SearchListRow(kind: .placemark(south), title: "Starbucks")

        #expect(northRow.id != southRow.id)
    }

    @Test
    func `Only a placemark row counts as a placemark`() {
        let place = place(latitude: 47.6, longitude: -122.3)

        #expect(SearchListRow.Kind.placemark(place).isPlacemark)
        #expect(!SearchListRow.Kind.searchResult(id: "1_75403").isPlacemark)
        #expect(!SearchListRow.Kind.recentStop(id: "1_75403").isPlacemark)
        #expect(!SearchListRow.Kind.loading.isPlacemark)
    }

    // MARK: - Stop subtitle

    @Test
    func `A stop's subtitle is its distance, then its direction`() throws {
        let application = try applicationWithFix()

        #expect(SearchListRow.stopSubtitle(application, try stop(direction: "N")) == "0.7 miles • Northbound")
    }

    @Test
    func `Without a location fix a stop's subtitle is just its direction`() throws {
        let application = try applicationWithoutFix()

        #expect(SearchListRow.stopSubtitle(application, try stop(direction: "W")) == "Westbound")
    }

    @Test
    func `A stop with no fix and no direction has no subtitle`() throws {
        let application = try applicationWithoutFix()

        #expect(SearchListRow.stopSubtitle(application, try stop(direction: nil)) == nil)
    }

    // MARK: - Map item subtitle

    @available(iOS 26.0, *)
    @Test
    func `A place's subtitle is its distance, then its short address`() throws {
        let application = try applicationWithFix()

        #expect(SearchListRow.subtitleForMapItem(application, mapItem(shortAddress: "1500 Broadway")) == "0.7 miles • 1500 Broadway")
    }

    @available(iOS 26.0, *)
    @Test
    func `Without a location fix a place's subtitle is just its address`() throws {
        let application = try applicationWithoutFix()

        #expect(SearchListRow.subtitleForMapItem(application, mapItem(shortAddress: "1500 Broadway")) == "1500 Broadway")
    }

    @available(iOS 26.0, *)
    @Test
    func `A place with no fix and no address has no subtitle`() throws {
        let application = try applicationWithoutFix()

        #expect(SearchListRow.subtitleForMapItem(application, mapItem(shortAddress: nil)) == nil)
    }

    // MARK: - Map item icon

    @Test func `A place with a category shows that category's symbol`() {
        let item = place(latitude: 47.6, longitude: -122.3)
        item.pointOfInterestCategory = .cafe

        #expect(systemName(SearchListRow.systemImageForMapItem(item)) == "cup.and.saucer")
    }

    @Test func `A place with no category shows a map pin`() {
        #expect(systemName(SearchListRow.systemImageForMapItem(place(latitude: 47.6, longitude: -122.3))) == "mappin")
    }
}
