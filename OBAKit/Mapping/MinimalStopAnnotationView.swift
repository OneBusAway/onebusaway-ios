//
//  MinimalStopAnnotationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import OBAKitCore

/// The dot for each stop on the trip map. The rider's stops are drawn larger in
/// the route's color, the same sizes the panel's trip map uses.
class MinimalStopAnnotationView: MKAnnotationView {

    /// How a stop's pin stands out from the rest of the trip. The trip map marks
    /// the stops the stop list marks; `TripMapAnnotationPolicy.StopMarks` decides
    /// which. See #449.
    enum Marking {
        /// A stop the rider neither boards nor leaves at.
        case ordinary
        /// The rider's stop: where they board, or on a shared trip, where the
        /// sharer steps off. Filled with the route's color.
        case riderStop
        /// Where the sharer boards, once a shared trip's rider's stop has moved
        /// to their destination. A ring in the route's color.
        case boardingStop
    }

    private let shapeLayer = CAShapeLayer()

    /// An arrival above the pin. Outside the pin's bounds, so a tap on it
    /// reaches the map rather than opening the stop.
    private let arrivalBadge = DepartureTimeBadge()

    // MARK: - Init

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        layer.addSublayer(shapeLayer)
        addSubview(arrivalBadge)

        configure(marking: .ordinary, routeColor: strokeColor, arrival: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Annotation View Overrides

    public override func prepareForReuse() {
        super.prepareForReuse()

        configure(marking: .ordinary, routeColor: strokeColor, arrival: nil)
    }

    // MARK: - Marking

    /// - Parameters:
    ///   - routeColor: What a marked pin is drawn in. Unused by an ordinary pin.
    ///   - arrival: Shown above the pin, or no badge when `nil`.
    func configure(marking: Marking, routeColor: UIColor, arrival: DepartureTimeBadge.Configuration?) {
        let isMarked = marking != .ordinary
        annotationSize = isMarked ? TripFocusMapLayer.Style.userStopDiameter : TripFocusMapLayer.Style.stopDiameter
        shapeLayer.lineWidth = isMarked ? TripFocusMapLayer.Style.stopRingWidth : Self.ordinaryRingWidth

        switch marking {
        case .ordinary:
            shapeLayer.fillColor = fillColor.cgColor
            shapeLayer.strokeColor = strokeColor.cgColor
        case .riderStop:
            shapeLayer.fillColor = routeColor.cgColor
            shapeLayer.strokeColor = fillColor.cgColor
        case .boardingStop:
            shapeLayer.fillColor = fillColor.cgColor
            shapeLayer.strokeColor = routeColor.cgColor
        }

        arrivalBadge.configure(arrival)
        arrivalBadge.isHidden = arrival == nil
        // A pin displaying an arrival badge sits above neighbouring stop dots
        // and the vehicle pin so its badge is never obscured. See #1513.
        zPriority = arrival != nil ? .max : .defaultUnselected
        setNeedsLayout()
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let bezierPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.width / 2.0)
        shapeLayer.path = bezierPath.cgPath
        shapeLayer.frame = bounds

        let badgeSize = arrivalBadge.intrinsicContentSize
        arrivalBadge.frame = CGRect(
            x: bounds.midX - badgeSize.width / 2.0,
            y: bounds.minY - badgeSize.height - ThemeMetrics.compactPadding,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }

    // MARK: - Appearance

    /// Sets the size of the receiver, which in turn configures its bounds and the frame of its contents.
    public var annotationSize: CGFloat {
        get { return bounds.size.width }
        set {
            bounds = CGRect(x: 0, y: 0, width: newValue, height: newValue)
            frame = frame.integral
        }
    }

    /// Fill color for this annotation.
    public var fillColor: UIColor = .white

    /// Stroke color for this annotation view and its directional arrow.
    public var strokeColor: UIColor = .gray

    private static let ordinaryRingWidth: CGFloat = 1.0
}
