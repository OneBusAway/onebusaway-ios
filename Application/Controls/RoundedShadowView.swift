//
//  RoundedShadowView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/20/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

fileprivate func buildShadowedShapeLayer() -> CAShapeLayer {
    let shadowLayer = CAShapeLayer()

    shadowLayer.fillColor = UIColor.white.cgColor
    shadowLayer.shadowColor = UIColor.black.cgColor
    shadowLayer.shadowOffset = CGSize(width: 0.0, height: 1.0)
    shadowLayer.shadowOpacity = 0.2
    shadowLayer.shadowRadius = 4.0

    shadowLayer.strokeColor = UIColor.white.cgColor
    shadowLayer.lineWidth = 2.0

    return shadowLayer
}

/// A container view that simplifies displaying both a drop shadow and rounded corners.
public class RoundedShadowView: UIView {
    private let contentLayer: CAShapeLayer = {
        let layer = buildShadowedShapeLayer()
        layer.cornerRadius = 4.0
        return layer
    }()

    public var cornerRadius: CGFloat {
        get {
            return contentLayer.cornerRadius
        }
        set {
            contentLayer.cornerRadius = newValue
        }
    }

    /// Use this instead of `backgroundColor` to set the background color of this view.
    public var fillColor: UIColor? {
        get {
            guard let c = contentLayer.fillColor else {
                return nil
            }
            return UIColor(cgColor: c)
        }
        set {
            contentLayer.fillColor = newValue?.cgColor
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(contentLayer)
        contentLayer.frame = bounds
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        contentLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        contentLayer.shadowPath = contentLayer.path
    }
}

public class TriangleShadowView: UIView {
    private let contentLayer = buildShadowedShapeLayer()

    public var fillColor: UIColor? {
        get {
            guard let c = contentLayer.fillColor else {
                return nil
            }
            return UIColor(cgColor: c)
        }
        set {
            contentLayer.fillColor = newValue?.cgColor
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(contentLayer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        contentLayer.frame = bounds
        contentLayer.path = createTriangle(rect: bounds).cgPath
        contentLayer.shadowPath = contentLayer.path
    }

    func createTriangle(rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()

        let midX = rect.width / 2.0
        let sz: CGFloat = 8.0

        path.move(to: CGPoint(x: rect.width / 2.0, y: 0.0))
        path.addLine(to: CGPoint(x: midX - sz, y: sz))
        path.addLine(to: CGPoint(x: midX + sz, y: sz))
        path.close()

        return path
    }
}
