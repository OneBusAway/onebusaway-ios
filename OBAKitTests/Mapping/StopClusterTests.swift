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

    @Test func `Stop pins share one clustering identifier across reuse`() {
        let view = StopAnnotationView(annotation: stops[0], reuseIdentifier: nil)
        #expect(view.clusteringIdentifier == StopCluster.clusteringIdentifier)

        view.clusteringIdentifier = nil
        view.prepareForReuse()
        #expect(view.clusteringIdentifier == StopCluster.clusteringIdentifier)

        view.clusteringIdentifier = nil
        view.prepareForDisplay()
        #expect(view.clusteringIdentifier == StopCluster.clusteringIdentifier)
    }

    @Test func `The cluster view shows how many stops it holds`() {
        let view = StopClusterAnnotationView(annotation: cluster([stops[0], stops[1], stops[2]]), reuseIdentifier: nil)
        view.prepareForDisplay()

        #expect(view.glyphText == "3")
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
