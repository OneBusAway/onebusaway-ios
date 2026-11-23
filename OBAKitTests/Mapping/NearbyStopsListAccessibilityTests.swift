//
//  NearbyStopsListAccessibilityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The nearby-stops list is a VoiceOver rider's main way to a stop. Its rows read
/// "Pine St & 3rd Ave (W)" as the letter W, weren't announced as buttons, and gave
/// no distance, and its section header wasn't a heading.
@MainActor
@Suite(.serialized)
final class NearbyStopsListAccessibilityTests {

    private final class DataSource: NearbyStopsListDataSource {
        var highSeverityAlerts: [AgencyAlert] = []
        var stops: [Stop] = []
        var userLocation: CLLocation?
    }

    private let dataSource = DataSource()
    private let stops: [Stop]

    init() throws {
        stops = Array(try Fixtures.loadSomeStops().prefix(3))
    }

    /// Cells in list order: the header, then one per stop.
    private func cells() throws -> [UICollectionViewCell] {
        let controller = NearbyStopsListViewController()
        controller.dataSource = dataSource
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 2000)
        controller.updateList()
        controller.view.layoutIfNeeded()

        let collectionView = try #require(controller.scrollView as? UICollectionView)
        return try (0...dataSource.stops.count).map { item in
            try #require(collectionView.cellForItem(at: IndexPath(item: item, section: 0)))
        }
    }

    @Test func `Stop rows say what the map pin says, and are buttons`() throws {
        dataSource.stops = stops
        let rows = try cells().dropFirst()

        for (row, stop) in zip(rows, stops) {
            let label = try #require(row.accessibilityLabel)
            #expect(label.hasPrefix(Formatters.formattedAccessibilityLabel(stop: stop)))
            #expect(row.accessibilityTraits.contains(.button))
            #expect(row.accessibilityHint == StopAnnotationView.accessibilityHint)
            #expect(row.accessibilityValue == nil)
        }
    }

    @Test func `Stop rows keep primary label uncluttered without duplicate alert`() throws {
        let stop = stops[0]
        let label = NearbyStopsListViewController.accessibilityLabel(for: stop, from: nil)
        #expect(!label.contains(Strings.serviceAlert))
    }

    @Test func `Stop rows give the distance from the rider when it's known`() throws {
        let stop = stops[0]
        dataSource.stops = [stop]
        let rider = CLLocation(latitude: stop.location.coordinate.latitude + 0.002, longitude: stop.location.coordinate.longitude)
        dataSource.userLocation = rider

        let row = try cells()[1]
        let distance = Formatters.spokenDistanceFormatter.string(fromDistance: stop.location.distance(from: rider))
        #expect(row.accessibilityLabel?.contains(distance) == true)
    }

    @Test func `The section header is a heading`() throws {
        dataSource.stops = stops
        let header = try cells()[0]
        #expect(header.accessibilityTraits.contains(.header))
        #expect(!header.accessibilityTraits.contains(.button))
    }

    private func makeAgencyAlert(id: String, title: String) throws -> AgencyAlert {
        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

        var titleTranslation = TransitRealtime_TranslatedString.Translation()
        titleTranslation.language = "en"
        titleTranslation.text = title

        var transitAlert = TransitRealtime_Alert()
        transitAlert.informedEntity = [entitySelector]
        transitAlert.headerText.translation = [titleTranslation]

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = id
        feedEntity.alert = transitAlert

        return try AgencyAlert(feedEntity: feedEntity, agency: nil)
    }

    @Test func `Alert rows clear accessibilityHint so reused cells do not keep stop hint`() throws {
        let alert = try makeAgencyAlert(id: "alert_1", title: "Snow route active")
        dataSource.highSeverityAlerts = [alert]
        dataSource.stops = [stops[0]]

        let controller = NearbyStopsListViewController()
        controller.dataSource = dataSource
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 2000)
        controller.updateList()
        controller.view.layoutIfNeeded()

        let collectionView = try #require(controller.scrollView as? UICollectionView)
        // Alert section is section 0; item 0 is header, item 1 is alert row.
        let alertRow = try #require(collectionView.cellForItem(at: IndexPath(item: 1, section: 0)))
        // Stops section is section 1; item 0 is header, item 1 is stop row.
        let stopRow = try #require(collectionView.cellForItem(at: IndexPath(item: 1, section: 1)))

        #expect(stopRow.accessibilityHint == StopAnnotationView.accessibilityHint)
        #expect(alertRow.accessibilityHint == nil)
    }
}
