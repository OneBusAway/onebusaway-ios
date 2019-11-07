//
//  MinimalStopAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/3/19.
//

import UIKit
import MapKit
import OBAKitCore

public class MinimalStopAnnotationView: MKAnnotationView {

    public var selectedArrivalDeparture: ArrivalDeparture?

    private let shapeLayer = CAShapeLayer()

    // MARK: - Init

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        layer.addSublayer(shapeLayer)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Annotation View Overrides

    public override func prepareForReuse() {
        super.prepareForReuse()

        shapeLayer.strokeColor = strokeColor.cgColor
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()

        guard
            let stop = annotation as? Stop,
            let selectedArrivalDeparture = selectedArrivalDeparture
        else {
            return
        }

        if selectedArrivalDeparture.stopID == stop.id {
            shapeLayer.strokeColor = highlightedStrokeColor.cgColor
        }

        /*
         This annotation view should be highlighted in highlightedStrokeColor if it is the stop that
         corresponds to the one that the user is looking at in the Trip Controller. I need to add in
         a way to detect whether it is the correct view or not.
         */
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let bezierPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.width / 2.0)
        shapeLayer.path = bezierPath.cgPath
        shapeLayer.frame = bounds

        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.fillColor = fillColor.cgColor
    }

    // MARK: - UIAppearance

    /// Sets the size of the receiver, which in turn configures its bounds and the frame of its contents.
    @objc dynamic var annotationSize: CGFloat {
        get { return bounds.size.width }
        set {
            bounds = CGRect(x: 0, y: 0, width: newValue, height: newValue)
            frame = frame.integral
        }
    }

    /// Fill color for this annotation.
    @objc dynamic var fillColor: UIColor {
        get { return _fillColor }
        set { _fillColor = newValue }
    }
    private var _fillColor: UIColor = .white

    /// Stroke color for this annotation view and its directional arrow.
    @objc dynamic var strokeColor: UIColor {
        get { return _strokeColor }
        set { _strokeColor = newValue }
    }
    private var _strokeColor: UIColor = .gray

    /// Stroke color for this annotation view when it is highlighted.
    @objc dynamic var highlightedStrokeColor: UIColor {
        get { return _highlightedStrokeColor }
        set { _highlightedStrokeColor = newValue }
    }
    private var _highlightedStrokeColor: UIColor = .red
}
