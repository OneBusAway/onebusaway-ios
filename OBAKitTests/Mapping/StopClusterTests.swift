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
}
