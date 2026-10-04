//
//  StopClusterAnnotationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// A brand-tinted marker counting the stops MapKit grouped under it.
final class StopClusterAnnotationView: MKMarkerAnnotationView {

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        markerTintColor = ThemeColors.shared.brand
        displayPriority = .defaultHigh
        collisionMode = .circle
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()

        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let stops = StopCluster.stops(in: cluster.memberAnnotations)
        glyphText = String(stops.count)
        accessibilityLabel = stops.map(\.name).joined(separator: ", ")
    }
}
