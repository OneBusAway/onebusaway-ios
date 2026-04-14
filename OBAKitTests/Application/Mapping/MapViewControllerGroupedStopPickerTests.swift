//
//  MapViewControllerGroupedStopPickerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import MapKit
@testable import OBAKit
@testable import OBAKitCore

final class MapViewControllerGroupedStopPickerTests: XCTestCase {
    func test_clusterStopMembers_dedupesAndPrioritizesBookmarkedStop() {
        let stopA = makeStop(id: "A", name: "Pine")
        let stopB = makeStop(id: "B", name: "Broadway")
        let bookmarkA = Bookmark(name: "Pinned", regionIdentifier: 1, stop: stopA)

        let members = MapViewController.clusterStopMembers(from: [stopA, stopB, bookmarkA])

        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(members.first?.stopID, "A")
        XCTAssertEqual(members.first?.isBookmarked, true)
    }

    func test_clusterStopMembers_ignoresNonStopAnnotations() {
        let point = MKPointAnnotation()
        point.coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let members = MapViewController.clusterStopMembers(from: [point])

        XCTAssertTrue(members.isEmpty)
    }

    func test_sortedClusterStopMembers_prioritizesBookmarkedThenTitleThenStopID() {
        let input = [
            MapViewController.ClusterStopMember(stopID: "3", title: "Pine", subtitle: nil, isBookmarked: false),
            MapViewController.ClusterStopMember(stopID: "2", title: "Pine", subtitle: nil, isBookmarked: true),
            MapViewController.ClusterStopMember(stopID: "1", title: "Broadway", subtitle: nil, isBookmarked: false)
        ]

        let sorted = MapViewController.sortedClusterStopMembers(input)

        XCTAssertEqual(sorted.map(\.stopID), ["2", "1", "3"])
    }

    func test_clusterStopActionTitle_includesSubtitleWhenPresent() {
        let withSubtitle = MapViewController.ClusterStopMember(stopID: "1", title: "Pine & 3rd", subtitle: "NW", isBookmarked: false)
        let withoutSubtitle = MapViewController.ClusterStopMember(stopID: "2", title: "Pine & 4th", subtitle: nil, isBookmarked: false)

        XCTAssertEqual(MapViewController.clusterStopActionTitle(for: withSubtitle), "Pine & 3rd (NW)")
        XCTAssertEqual(MapViewController.clusterStopActionTitle(for: withoutSubtitle), "Pine & 4th")
    }

    private func makeStop(id: String, name: String) -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "code": id,
            "name": name,
            "lat": 47.6,
            "lon": -122.3,
            "direction": "N",
            "locationType": 0,
            "routeIds": [],
            "wheelchairBoarding": "unknown"
        ]

        let data = try! JSONSerialization.data(withJSONObject: dict) // swiftlint:disable:this force_try
        let stop = try! JSONDecoder().decode(Stop.self, from: data) // swiftlint:disable:this force_try
        stop.routes = []
        return stop
    }
}
