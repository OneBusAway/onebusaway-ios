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
        // White on OneBusAway's green is under 3:1; take whichever of white or
        // black clears 4.5:1 on the white-label app's brand.
        glyphTintColor = ThemeColors.shared.brand.badgeTextColor(preferring: .white, minimumRatio: 4.5)
        displayPriority = .defaultHigh
        collisionMode = .circle
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MKMarkerAnnotationView's getter answers its own "Shows more info" and
    // ignores what was assigned, so VoiceOver would never hear the cluster hint.
    private var clusterHint: String?
    override var accessibilityHint: String? {
        get { clusterHint ?? super.accessibilityHint }
        set { clusterHint = newValue }
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()

        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let stops = StopCluster.stops(in: cluster.memberAnnotations)
        glyphText = String(stops.count)
        accessibilityLabel = StopCluster.accessibilityLabel(stopCount: stops.count)
        accessibilityValue = StopCluster.accessibilityValue(for: stops)
        accessibilityHint = StopCluster.accessibilityHint
        accessibilityTraits = .button
    }
}
