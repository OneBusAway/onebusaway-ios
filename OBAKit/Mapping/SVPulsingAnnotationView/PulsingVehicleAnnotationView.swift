//
//  PulsingVehicleAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/4/19.
//

import UIKit
import OBAKitCore

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
    }

    override var tintColor: UIColor! {
        didSet {
            imageView.tintColor = tintColor
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var routeType: RouteType {
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
            guard let annotation = annotation as? TripStatus else { return }

            // n.b. The coordinate system that Core Graphics uses on iOS for transforms is backwards from what
            // you would normally expect, and backwards from what the OBA API vends. Long story short: instead
            // of generating *exactly backwards* data at the model layer, we'll just flip it here instead.
            // Long story short, negate your orientation in order to have it look right.
            headingImageView.transform = CGAffineTransform(rotationAngle: CGFloat(-annotation.orientation.radians))

            routeType = annotation.activeTrip.route.routeType
            isRealTime = annotation.isRealTime
        }
    }

    // MARK: - UIAppearance

    /// The annotation color for a vehicle with available real-time data.
    @objc dynamic var realTimeAnnotationColor: UIColor {
        get { return _realTimeAnnotationColor }
        set {
            _realTimeAnnotationColor = newValue
            if isRealTime {
                annotationColor = newValue
            }
        }
    }
    private var _realTimeAnnotationColor: UIColor = .green

    /// The annotation color for a vehicle without available real-time data.
    @objc dynamic var scheduledAnnotationColor: UIColor {
        get { return _scheduledAnnotationColor }
        set {
            _scheduledAnnotationColor = newValue
            if !isRealTime {
                annotationColor = newValue
            }
        }
    }
    private var _scheduledAnnotationColor: UIColor = .gray
}
