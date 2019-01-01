//
//  IndeterminateProgressView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/1/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

/*
 Loosely based on M13ProgressView

 Copyright (c) 2013 Brandon McQuilkin

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

public class IndeterminateProgressView: UIView {

    /// The thickness of the progress bar.
    var progressBarThickness: CGFloat = 5.0 {
        didSet {
            setNeedsDisplay()
            invalidateIntrinsicContentSize()
        }
    }

    /// The corner radius of the progress bar.
    var progressBarCornerRadius: CGFloat {
        return progressBarThickness / 2.0
    }

    private var _progressColor: UIColor = UIColor(red: 0, green: 122 / 255.0, blue: 1.0, alpha: 1.0) {
        didSet {
            indeterminateLayer.backgroundColor = _progressColor.cgColor
        }
    }
    @objc dynamic var progressColor: UIColor {
        get { return _progressColor }
        set { _progressColor = newValue }
    }

    public var animationDuration: TimeInterval = 0.3

    private lazy var progressBar: UIView = {
        let progressBar = UIView()
        progressBar.backgroundColor = .clear
        progressBar.layer.cornerRadius = progressBarCornerRadius
        progressBar.clipsToBounds = false
        progressBar.layer.addSublayer(indeterminateLayer)
        return progressBar
    }()

    /// The layer that is used to animate indeterminate progress.
    private lazy var indeterminateLayer: CALayer = {
        let indeterminateLayer = CALayer()
        indeterminateLayer.backgroundColor = progressColor.cgColor
        indeterminateLayer.cornerRadius = progressBarCornerRadius
        indeterminateLayer.opacity = 0
        return indeterminateLayer
    }()

    // MARK: Initalization and setup

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(progressBar)
        layoutSubviews()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        addSubview(progressBar)
        setNeedsLayout()
    }

    private func buildIndeterminateAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "position")
        animation.duration = 5 * animationDuration
        animation.repeatCount = Float.greatestFiniteMagnitude
        animation.isRemovedOnCompletion = true
        // Set the animation control points
        if layoutDirectionIsLTR {
            animation.fromValue = NSValue(cgPoint: CGPoint(x: -indeterminateLayer.frame.width, y: 0))
            animation.toValue = NSValue(cgPoint: CGPoint(x: indeterminateLayer.frame.width + progressBar.bounds.width, y: 0))
        }
        else {
            animation.fromValue = NSValue(cgPoint: CGPoint(x: indeterminateLayer.frame.width + progressBar.bounds.width, y: 0))
            animation.toValue = NSValue(cgPoint: CGPoint(x: -indeterminateLayer.frame.width, y: 0))
        }
        return animation
    }

    // MARK: Layout
    override public func layoutSubviews() {
        super.layoutSubviews()

        var frame = bounds
        frame.origin.x = 10
        frame.size.width -= 20
        frame.size.height = progressBarThickness
        progressBar.frame = frame
        
        indeterminateLayer.removeAllAnimations()
        indeterminateLayer.frame = CGRect(x: 0, y: 0, width: progressBar.frame.width * 0.2, height: frame.size.height)

        //show the indeterminate view
        indeterminateLayer.opacity = 1
        //Create the animation
        let animation = buildIndeterminateAnimation()
        indeterminateLayer.add(animation, forKey: "position")
    }

    override public var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: progressBarThickness)
    }
}
