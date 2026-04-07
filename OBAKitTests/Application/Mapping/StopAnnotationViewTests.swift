//
//  StopAnnotationViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

final class StopAnnotationViewTests: XCTestCase {
    func test_init_setsClusteringIdentifier() {
        let view = StopAnnotationView(annotation: nil, reuseIdentifier: "stop")

        XCTAssertEqual(view.clusteringIdentifier, StopAnnotationView.stopClusterIdentifier)
    }

    func test_prepareForReuse_keepsClusteringIdentifier() {
        let view = StopAnnotationView(annotation: nil, reuseIdentifier: "stop")
        view.clusteringIdentifier = nil

        view.prepareForReuse()

        XCTAssertEqual(view.clusteringIdentifier, StopAnnotationView.stopClusterIdentifier)
    }

    func test_prepareForDisplay_stop_keepsClusteringIdentifier() {
        let stop = makeStop(id: "1", name: "Pine")
        let view = StopAnnotationView(annotation: stop, reuseIdentifier: "stop")
        view.delegate = MockStopAnnotationDelegate()
        view.clusteringIdentifier = nil

        view.prepareForDisplay()

        XCTAssertEqual(view.clusteringIdentifier, StopAnnotationView.stopClusterIdentifier)
    }

    func test_prepareForDisplay_bookmark_keepsClusteringIdentifier() {
        let stop = makeStop(id: "2", name: "Broadway")
        let bookmark = Bookmark(name: "Pinned Stop", regionIdentifier: 1, stop: stop)
        let view = StopAnnotationView(annotation: bookmark, reuseIdentifier: "stop")
        view.delegate = MockStopAnnotationDelegate()
        view.clusteringIdentifier = nil

        view.prepareForDisplay()

        XCTAssertEqual(view.clusteringIdentifier, StopAnnotationView.stopClusterIdentifier)
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

private final class MockStopAnnotationDelegate: StopAnnotationDelegate {
    let iconFactory = StopIconFactory(
        iconSize: ThemeMetrics.defaultMapAnnotationSize,
        themeColors: ThemeColors.shared
    )

    func isStopBookmarked(_ stop: Stop) -> Bool {
        false
    }

    var shouldHideExtraStopAnnotationData: Bool {
        true
    }
}
