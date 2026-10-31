//
//  PulsingVehicleAnnotationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import MapKit

/// A map annotation view that represents the location and heading of a vehicle (bus, train, etc.)
class PulsingVehicleAnnotationView: PulsingAnnotationView {

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        routeType = .unknown
        isRealTime = true

        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        bounds = frame.integral

        imageView.frame = bounds.insetBy(dx: 8.0, dy: 8.0)

        canShowCallout = true

        imageView.tintColor = .white
        headingImage = Icons.templateHeading

        isUserInteractionEnabled = false
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Whether this marker can be tapped to select it.
    ///
    /// Off by default: the trip screen only ever *displays* these markers, and
    /// turning selection on there would start showing a title-only callout it was
    /// never designed for. The stop-route-focus layer opts in.
    var isSelectable: Bool = false {
        didSet { isUserInteractionEnabled = isSelectable }
    }

    public var routeType: Route.RouteType {
        didSet {
            image = Icons.transportIcon(from: routeType)
        }
    }

    public var isRealTime: Bool {
        didSet {
            if isRealTime {
                annotationColor = realTimeAnnotationColor
                delayBetweenPulseCycles = 0
            }
            else {
                annotationColor = ThemeColors.shared.gray
                delayBetweenPulseCycles = Double.infinity
            }
        }
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard
                let annotation = annotation as? VehicleAnnotation,
                let tripStatus = annotation.tripStatus
            else { return }

            applyTripStatus(tripStatus)
        }
    }

    /// Updates the annotation view to reflect the current trip status.
    /// Call this when the underlying `VehicleAnnotation.tripStatus` has been
    /// updated in-place so that heading, route type, and real-time state
    /// are refreshed without re-creating the annotation.
    func applyTripStatus(_ tripStatus: TripStatus) {
        updateHeading(tripStatus: tripStatus)
        routeType = tripStatus.activeTrip.route.routeType
        isRealTime = tripStatus.isRealTime
    }

    // MARK: - Heading

    private func updateHeading(tripStatus: TripStatus) {
        guard tripStatus.isRealTime else {
            headingImageView.isHidden = true
            return
        }

        headingImageView.tintColor = realTimeAnnotationColor

        // n.b. The coordinate system that Core Graphics uses on iOS for transforms is backwards from what
        // you would normally expect, and backwards from what the OBA API vends. Long story short: instead
        // of generating *exactly backwards* data at the model layer, we'll just flip it here instead.
        // Long story short, negate your orientation in order to have it look right.

        let orientation = CGFloat(-tripStatus.orientation.radians)
        headingImageView.transform = CGAffineTransform(rotationAngle: orientation)

        headingImageView.isHidden = false
    }

    // MARK: - Estimated position

    /// Points the marker along the shape and shows the fix's age, for a vehicle
    /// whose position is estimated. `nil` puts back what `applyTripStatus` drew.
    ///
    /// Call after `applyTripStatus`, which resets the heading to the feed's.
    func applyEstimate(_ estimate: VehicleEstimate?) {
        let staleness = VehicleMarkerStaleness(estimate: estimate)
        alpha = staleness.alpha

        if isRealTime {
            let wantedDelay = staleness.pulseDelay
            if delayBetweenPulseCycles != wantedDelay { delayBetweenPulseCycles = wantedDelay }
        }

        if let orientation = estimate?.obaOrientation, isRealTime {
            // Negated for the same reason as in `updateHeading(tripStatus:)`.
            headingImageView.transform = CGAffineTransform(rotationAngle: CGFloat(-orientation.radians))
            headingImageView.isHidden = !staleness.showsHeading
        } else if !staleness.showsHeading {
            headingImageView.isHidden = true
        }

        setUncertaintyHalo(diameter: staleness.haloDiameter)
    }

    /// A recycled view may have shown another vehicle's stale estimate.
    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1
        setUncertaintyHalo(diameter: 0)
    }

    private lazy var uncertaintyLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.lineWidth = 1
        return layer
    }()

    /// The halo's current size, in points. 0 when there is none.
    private(set) var uncertaintyHaloDiameter: CGFloat = 0

    private func setUncertaintyHalo(diameter: CGFloat) {
        guard diameter != uncertaintyHaloDiameter else { return }
        uncertaintyHaloDiameter = diameter
        guard diameter > 0 else {
            uncertaintyLayer.removeFromSuperlayer()
            return
        }
        if uncertaintyLayer.superlayer == nil { layer.insertSublayer(uncertaintyLayer, at: 0) }
        let rect = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        uncertaintyLayer.path = UIBezierPath(ovalIn: rect).cgPath
        uncertaintyLayer.fillColor = realTimeAnnotationColor.withAlphaComponent(0.15).cgColor
        uncertaintyLayer.strokeColor = realTimeAnnotationColor.withAlphaComponent(0.35).cgColor
    }

    // MARK: - Appearance

    /// The annotation color for a vehicle with available real-time data.
    ///
    /// Re-applies on assignment. Without this, a caller that sets the color
    /// *after* assigning the annotation gets the previous route's color on a
    /// recycled view: `isRealTime`'s didSet is the only writer of
    /// `annotationColor`, and it runs when the annotation is assigned.
    /// `TripViewController.swift:419-423` has exactly that ordering today.
    public var realTimeAnnotationColor: UIColor = ThemeColors.shared.brand {
        didSet {
            guard isRealTime else { return }
            annotationColor = realTimeAnnotationColor
            headingImageView.tintColor = realTimeAnnotationColor
        }
    }

    /// The annotation color for a vehicle without available real-time data.
    public var scheduledAnnotationColor: UIColor = ThemeColors.shared.gray
}
