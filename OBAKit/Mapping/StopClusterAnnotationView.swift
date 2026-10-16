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
        applyStyle()
    }

    /// `MKMarkerAnnotationView` resets both tints to MapKit's stock red here, and
    /// recycled clusters drew in it (#1552). Everything `init` sets is reapplied,
    /// not just the tints, so nothing else it resets goes stale the same way.
    override func prepareForReuse() {
        super.prepareForReuse()
        applyStyle()
    }

    private func applyStyle() {
        displayPriority = .defaultHigh
        collisionMode = .circle
        markerTintColor = ThemeColors.shared.brand
        // White on OneBusAway's green is under 3:1; take whichever of white or
        // black clears 4.5:1 on the white-label app's brand.
        glyphTintColor = ThemeColors.shared.brand.badgeTextColor(preferring: .white, minimumRatio: 4.5)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MKMarkerAnnotationView's getter answers its own "Shows more info" and
    // ignores what was assigned, so VoiceOver would never hear the cluster hint.
    override var accessibilityHint: String? {
        get { annotation is MKClusterAnnotation ? StopCluster.accessibilityHint : super.accessibilityHint }
        set { super.accessibilityHint = newValue }
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()

        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let stops = StopCluster.stops(in: cluster.memberAnnotations)
        glyphText = String(stops.count)
        accessibilityLabel = StopCluster.accessibilityLabel(stopCount: stops.count)
        accessibilityValue = StopCluster.accessibilityValue(for: stops)
        accessibilityTraits = .button
    }
}
