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
        isUserInteractionEnabled = false

        imageView.tintColor = .white
        headingImage = Icons.templateHeading
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

            updateHeading(tripStatus: tripStatus)

            routeType = tripStatus.activeTrip.route.routeType
            isRealTime = tripStatus.isRealTime
        }
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

    // MARK: - Appearance

    /// The annotation color for a vehicle with available real-time data.
    public var realTimeAnnotationColor: UIColor = ThemeColors.shared.brand

    /// The annotation color for a vehicle without available real-time data.
    public var scheduledAnnotationColor: UIColor = ThemeColors.shared.gray
}
