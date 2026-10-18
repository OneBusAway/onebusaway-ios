//
//  StopClusterTests.swift
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

/// Stops at the same location used to draw one pin on top of another, so the
/// buried stop couldn't be tapped. Stop pins now cluster, and a cluster that
/// zooming can't separate offers a list instead.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/515
@MainActor
@Suite(.serialized)
final class StopClusterTests {

    private let stops: [Stop]

    init() throws {
        stops = try Fixtures.loadSomeStops()
    }

    private func cluster(_ members: [MKAnnotation]) -> MKClusterAnnotation {
        MKClusterAnnotation(memberAnnotations: members)
    }

    // MARK: - Identifying stop clusters

    @Test func `A cluster of stops and bookmarks is a stop cluster`() {
        let bookmark = Bookmark(name: "Home", regionIdentifier: 1, stop: stops[0])
        #expect(StopCluster.isStopCluster(cluster([bookmark, stops[1]])))
    }

    @Test func `A cluster of anything else is not a stop cluster`() {
        let pin = MKPointAnnotation()
        #expect(!StopCluster.isStopCluster(cluster([pin, MKPointAnnotation()])))
        #expect(!StopCluster.isStopCluster(stops[0]))
    }

    // MARK: - Members

    @Test func `A bookmarked stop is listed once, under the stop`() {
        let bookmark = Bookmark(name: "Home", regionIdentifier: 1, stop: stops[0])

        let listed = StopCluster.stops(in: [bookmark, stops[0], stops[1]])

        #expect(listed.map(\.id).sorted() == [stops[0].id, stops[1].id].sorted())
    }

    @Test func `Members are listed in a stable order regardless of map order`() {
        let forward = StopCluster.stops(in: [stops[0], stops[1], stops[2]])
        let reversed = StopCluster.stops(in: [stops[2], stops[1], stops[0]])

        #expect(forward.map(\.id) == reversed.map(\.id))
    }

    // MARK: - Co-location

    @Test func `Members at the same coordinate are co-located`() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        #expect(StopCluster.areCoLocated([coordinate, coordinate, coordinate]))
    }

    @Test func `Members a few meters apart are co-located`() {
        let first = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        let second = CLLocationCoordinate2D(latitude: 47.60005, longitude: -122.33)  // ~5.6 m north

        #expect(StopCluster.areCoLocated([first, second]))
    }

    @Test func `Members a block apart are not co-located, because zooming separates them`() {
        let first = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        let second = CLLocationCoordinate2D(latitude: 47.601, longitude: -122.33)  // ~111 m north

        #expect(!StopCluster.areCoLocated([first, second]))
    }

    @Test func `Any far-apart pair makes the cluster not co-located`() {
        let base = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        let far = CLLocationCoordinate2D(latitude: 47.601, longitude: -122.33)

        #expect(!StopCluster.areCoLocated([base, base, far]))
    }

    // MARK: - Picker titles

    @Test func `Picker titles carry the code and direction that tell co-located stops apart`() {
        let stop = stops[0]
        let title = StopCluster.pickerTitle(for: stop)

        #expect(title.hasPrefix(stop.name))
        #expect(title.contains(Formatters.formattedCodeAndDirection(stop: stop)))
    }

    // MARK: - Annotation views

    @Test func `Stop pins share one clustering identifier across reuse when clustering is on`() {
        let delegate = ClusteringDelegateStub(clustersStops: true)
        let view = StopAnnotationView(annotation: stops[0], reuseIdentifier: nil)
        view.delegate = delegate
        view.prepareForDisplay()
        #expect(view.clusteringIdentifier == StopCluster.clusteringIdentifier)

        view.prepareForReuse()
        view.prepareForDisplay()
        #expect(view.clusteringIdentifier == StopCluster.clusteringIdentifier)
    }

    @Test func `Stop pins don't cluster when clustering is off`() {
        let delegate = ClusteringDelegateStub(clustersStops: false)
        let view = StopAnnotationView(annotation: stops[0], reuseIdentifier: nil)
        #expect(view.clusteringIdentifier == nil)

        view.delegate = delegate
        view.prepareForDisplay()
        #expect(view.clusteringIdentifier == nil)
    }

    @Test func `The cluster view shows how many stops it holds`() {
        let view = StopClusterAnnotationView(annotation: cluster([stops[0], stops[1], stops[2]]), reuseIdentifier: nil)
        view.prepareForDisplay()

        #expect(view.glyphText == "3")
    }

    // MARK: - Brand tint (#1552)

    /// `prepareForReuse()` resets a marker's tints to MapKit's stock red.
    @Test func `A recycled cluster view keeps the brand tint`() {
        let view = StopClusterAnnotationView(annotation: cluster([stops[0], stops[1]]), reuseIdentifier: nil)
        view.prepareForDisplay()
        let brandGlyph = view.glyphTintColor

        view.prepareForReuse()
        view.annotation = cluster([stops[2], stops[3]])

        #expect(view.markerTintColor == ThemeColors.shared.brand)
        #expect(view.glyphTintColor == brandGlyph)
    }

    /// The same through real MapKit: the second zoom-out builds its clusters from
    /// recycled views.
    @Test func `Clusters keep the brand tint across zoom cycles`() async throws {
        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        mapView.registerAnnotationView(StopAnnotationView.self)
        mapView.registerAnnotationView(StopClusterAnnotationView.self)
        let delegate = StopClusterMapDelegate()
        mapView.delegate = delegate

        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = mapView.frame
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(mapView)
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func clusterViews() -> [StopClusterAnnotationView] {
            mapView.annotations(in: mapView.visibleMapRect)
                .compactMap { $0 as? MKClusterAnnotation }
                .compactMap { mapView.view(for: $0) as? StopClusterAnnotationView }
        }

        mapView.addAnnotations(stops)
        var firstPass: Set<ObjectIdentifier> = []
        for (span, clustered) in [(0.06, true), (0.004, false), (0.06, true)] {
            mapView.setRegion(
                MKCoordinateRegion(center: stops[0].coordinate, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)),
                animated: false
            )
            await poll(until: { clusterViews().isEmpty != clustered }, timeout: .seconds(5), "clusters never \(clustered ? "formed" : "broke up")")
            if firstPass.isEmpty { firstPass = Set(clusterViews().map(ObjectIdentifier.init)) }
        }
        let views = clusterViews()
        try #require(!views.isEmpty, "the fixture's stops formed no clusters")
        // Without a recycled view this would pass on fresh ones and prove nothing.
        try #require(views.contains { firstPass.contains(ObjectIdentifier($0)) }, "no cluster view was recycled")
        for view in views {
            #expect(view.markerTintColor == ThemeColors.shared.brand)
        }
    }

    // MARK: - Accessibility

    @Test func `Under VoiceOver every cluster lists its stops instead of zooming`() {
        let first = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.33)
        let blockAway = CLLocationCoordinate2D(latitude: 47.601, longitude: -122.33)

        #expect(!StopCluster.listsStopsOnSelection([first, blockAway], isVoiceOverRunning: false))
        #expect(StopCluster.listsStopsOnSelection([first, blockAway], isVoiceOverRunning: true))
        #expect(StopCluster.listsStopsOnSelection([first, first], isVoiceOverRunning: false))
    }

    @Test func `The cluster label is a pluralized stop count`() {
        #expect(StopCluster.accessibilityLabel(stopCount: 1) == "1 stop")
        #expect(StopCluster.accessibilityLabel(stopCount: 4) == "4 stops")
    }

    @Test func `The cluster value names the first few distinct stops`() {
        let value = StopCluster.accessibilityValue(for: Array(stops.prefix(5)))
        let distinctNames = Array(NSOrderedSet(array: stops.prefix(5).map(\.name))) as? [String] ?? []

        for name in distinctNames.prefix(StopCluster.accessibilityValueNameLimit) {
            #expect(value.contains(name))
        }
        for name in distinctNames.dropFirst(StopCluster.accessibilityValueNameLimit) {
            #expect(!value.contains(name))
        }
    }

    @Test func `Co-located stops sharing a name are named once`() {
        let value = StopCluster.accessibilityValue(for: [stops[0], stops[0]])
        #expect(value == stops[0].name)
    }

    @Test func `The cluster view is a labelled button with a value and hint`() {
        let view = StopClusterAnnotationView(annotation: cluster([stops[0], stops[1]]), reuseIdentifier: nil)
        view.prepareForDisplay()

        #expect(view.accessibilityLabel == "2 stops")
        #expect(view.accessibilityValue == StopCluster.accessibilityValue(for: StopCluster.stops(in: [stops[0], stops[1]])))
        #expect(view.accessibilityHint == StopCluster.accessibilityHint)
        #expect(view.accessibilityTraits.contains(.button))
    }

    @Test func `A bookmark pin reads as its stop, led by the bookmark name`() {
        let bookmark = Bookmark(name: "Home", regionIdentifier: 1, stop: stops[0])
        let label = StopAnnotationView.accessibilityLabel(for: bookmark)

        #expect(label == Formatters.formattedAccessibilityLabel(stop: stops[0], bookmarkName: "Home"))
        #expect(label?.hasPrefix("Home") == true)
    }

    @Test func `A stop pin keeps its stop label, and anything else falls back`() {
        #expect(StopAnnotationView.accessibilityLabel(for: stops[0]) == Formatters.formattedAccessibilityLabel(stop: stops[0]))
        #expect(StopAnnotationView.accessibilityLabel(for: MKPointAnnotation()) == nil)
    }
}

/// Stop clustering is opt-in (#1600); `MapRegionManager` answers from the Settings flag.
private final class ClusteringDelegateStub: NSObject, StopAnnotationDelegate {
    let clustersStops: Bool
    let showsStopAnnotationCallouts = true
    let shouldHideExtraStopAnnotationData = true
    let iconFactory = StopIconFactory(iconSize: 48.0, themeColors: ThemeColors.shared)

    init(clustersStops: Bool) {
        self.clustersStops = clustersStops
    }

    func isStopBookmarked(_ stop: Stop) -> Bool { false }
}

/// Stands in for `MapRegionManager.mapView(_:viewFor:)` for stops and their clusters.
@MainActor
private final class StopClusterMapDelegate: NSObject, MKMapViewDelegate {
    private let stopDelegate = ClusteringDelegateStub(clustersStops: true)

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        switch annotation {
        case is MKClusterAnnotation:
            return mapView.dequeueReusableAnnotationView(withIdentifier: MKMapView.reuseIdentifier(for: StopClusterAnnotationView.self), for: annotation)
        case is Stop:
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapView.reuseIdentifier(for: StopAnnotationView.self), for: annotation)
            if let stopView = view as? StopAnnotationView {
                stopView.delegate = stopDelegate
                stopView.applyPresentation()
            }
            return view
        default:
            return nil
        }
    }
}
