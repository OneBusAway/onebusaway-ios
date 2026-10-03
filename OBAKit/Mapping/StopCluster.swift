//
//  StopCluster.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// MapKit clusters stop pins that would draw on top of each other. These are
/// the decisions about those clusters, kept free of `MKMapView` so they can be
/// tested directly.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/515
enum StopCluster {

    /// Shared by `Stop` and `Bookmark` pins, so a bookmark and the stop beside
    /// it cluster together. Rentals use their own identifier and never mix in.
    static let clusteringIdentifier = "stops"

    /// Members closer than this can't be separated by zooming in, so tapping
    /// their cluster lists them instead.
    static let coLocatedToleranceMeters: CLLocationDistance = 15

    static func isStopCluster(_ annotation: MKAnnotation) -> Bool {
        guard let cluster = annotation as? MKClusterAnnotation else { return false }
        return cluster.memberAnnotations.allSatisfy { $0 is Stop || $0 is Bookmark }
    }

    /// The distinct stops among `members`, sorted by name and then ID so the list
    /// doesn't reorder as MapKit regroups. A bookmarked stop is listed once.
    static func stops(in members: [MKAnnotation]) -> [Stop] {
        var stopsByID: [StopID: Stop] = [:]
        for member in members {
            switch member {
            case let stop as Stop: stopsByID[stop.id] = stop
            case let bookmark as Bookmark: stopsByID[bookmark.stopID] = bookmark.stop
            default: continue
            }
        }

        return stopsByID.values.sorted {
            ($0.name, $0.id) < ($1.name, $1.id)
        }
    }

    static func areCoLocated(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
        let locations = coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        for (index, location) in locations.enumerated() {
            for other in locations[(index + 1)...] where location.distance(from: other) > coLocatedToleranceMeters {
                return false
            }
        }
        return true
    }

    /// Co-located stops usually share a name, so the title adds the code and
    /// direction that tell them apart.
    static func pickerTitle(for stop: Stop) -> String {
        "\(stop.name) · \(Formatters.formattedCodeAndDirection(stop: stop))"
    }
}
