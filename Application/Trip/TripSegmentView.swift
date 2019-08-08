//
//  TripSegmentView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/6/19.
//

import UIKit

/// The line/circle adornment on the leading side of a cell on the `TripDetailsController`.
///
/// Depicts if the associated stop is the user's destination or the current location of the transit vehicle.
public class TripSegmentView: UIView {

    private let lineWidth: CGFloat = 2.0
    private let circleRadius: CGFloat = 30.0
    private let imageInset: CGFloat = 6.0

    /// This is the color that is used to highlight a value change in this label.
    @objc public dynamic var lineColor: UIColor {
        get { return _lineColor }
        set { _lineColor = newValue }
    }
    private var _lineColor: UIColor = .gray

    /// This is the color that is used to highlight a value change in this label.
    @objc public dynamic var imageColor: UIColor {
        get { return _imageColor }
        set { _imageColor = newValue }
    }
    private var _imageColor: UIColor = .green

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var image: UIImage? {
        didSet {
            setNeedsDisplay()
        }
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: circleRadius + (2.0 * lineWidth), height: UIView.noIntrinsicMetric)
    }

    override public func draw(_ rect: CGRect) {
        super.draw(rect)

        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()

        lineColor.setFill()
        lineColor.setStroke()

        let halfRadius = circleRadius / 2.0

        let topLine = UIBezierPath(rect: CGRect(origin: CGPoint(x: rect.midX - (lineWidth / 2.0), y: rect.minY), size: CGSize(width: lineWidth, height: rect.midY - halfRadius)))
        topLine.fill()

        let circleRect = CGRect(origin: CGPoint(x: rect.midX - halfRadius, y: rect.midY - halfRadius), size: CGSize(width: circleRadius, height: circleRadius))
        let circle = UIBezierPath(ovalIn: circleRect)
        circle.lineWidth = lineWidth
        circle.stroke()

        if var image = image {
            if #available(iOS 13.0, *) {
                image = image.withTintColor(imageColor, renderingMode: .alwaysTemplate)
            }
            image.draw(in: circleRect.insetBy(dx: imageInset, dy: imageInset))
        }

        let bottomLine = UIBezierPath(rect: CGRect(origin: CGPoint(x: rect.midX - (lineWidth / 2.0), y: rect.midY + halfRadius), size: CGSize(width: lineWidth, height: rect.midY - halfRadius)))
        bottomLine.fill()

        ctx?.restoreGState()
    }
}
