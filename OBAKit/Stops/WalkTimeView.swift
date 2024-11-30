//
//  WalkTimeView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import OBAKitCore

/// Gives the user an indication of which vehicles they will be able to catch from the stop they are viewing.
class WalkTimeView: UIView {

    private let kUseDebugColors = false

    private let label: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .right
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = ThemeColors.shared.lightText
        label.setCompressionResistance(horizontal: .required, vertical: .required)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var triangleHeight = ThemeMetrics.padding
    private lazy var triangleVertexWidth = 1.5 * triangleHeight

    private let walkerImageInset: CGFloat = 8.0

    private let walkerImageView: UIImageView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.image = Icons.walkTransport
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.setHugging(horizontal: .required, vertical: .defaultHigh)

        return imageView
    }()

    public var formatters: Formatters!

    /// Background color of the background bar and triangle views.
    public var backgroundBarColor = ThemeColors.shared.brand

    override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        backgroundColor = .clear

        if kUseDebugColors {
            label.backgroundColor = .blue
            walkerImageView.backgroundColor = .red
            backgroundColor = .magenta
        }

        addSubview(label)
        addSubview(walkerImageView)

        NSLayoutConstraint.activate([
            walkerImageView.topAnchor.constraint(equalTo: topAnchor, constant: ThemeMetrics.ultraCompactPadding),
            walkerImageView.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor, constant: -walkerImageInset - 5.0),
            walkerImageView.heightAnchor.constraint(equalToConstant: 16.0),
            walkerImageView.widthAnchor.constraint(equalToConstant: 16.0),

            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -triangleHeight),
            label.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: walkerImageView.leadingAnchor, constant: -ThemeMetrics.padding)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        
        let sizeTraits: [UITrait] = [UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]
        registerForTraitChanges(sizeTraits) { (self: Self, previousTraitCollection: UITraitCollection) in
            self.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func set(distance: CLLocationDistance, timeToWalk: TimeInterval) {
        // bail out if the distance is 40 meters or less. Just don't show anything because
        // it suggests the user is essentially at the stop and showing '100 feet arriving in 1
        // min' looks weird.
        guard distance > 40 else {
            label.text = nil
            isAccessibilityElement = false
            return
        }

        let distanceString = formatters.distanceFormatter.string(fromDistance: distance)
        let arrivalTime = formatters.timeFormatter.string(from: Date().addingTimeInterval(timeToWalk))

        if let timeString = formatters.positionalTimeFormatter.string(from: timeToWalk) {
            let fmt = OBALoc("walk_time_view.distance_time_fmt", value: "%@, %@: arriving at %@", comment: "Format string with placeholders for distance from stop, walking time to stop, and predicted arrival time. e.g. 1.2 miles, 17m: arriving at 09:41 A.M.")
            label.text = String(format: fmt, distanceString, timeString, arrivalTime)
        }
        else {
            label.text = distanceString
        }

        accessibilityLabel = OBALoc("walk_time_view.accessibility_label", value: "Time to walk to stop", comment: "A label for blind or low-vision users on the UI element that describes how long it takes to walk to the stop.")
        accessibilityTraits = [.staticText]
        isAccessibilityElement = true

        if let timeString = formatters.accessibilityPositionalTimeFormatter.string(from: timeToWalk) {
            let fmt = OBALoc("walk_time_view.accessibility_value", value: "%@. Takes %@ to walk, arriving at %@", comment: "Accessibility string with placeholders for distance from stop, walking time to stop, and predicted arrival time. e.g. 1.2 miles. Takes 17 minutes to walk, arriving at 9:41 am")
            accessibilityValue = String(format: fmt, distanceString, timeString, arrivalTime)
        }
        else {
            accessibilityValue = distanceString
        }
    }

    private var maximumIntrinsicHeight: CGFloat = 24.0

    public override var intrinsicContentSize: CGSize {
        let intrinsic = super.intrinsicContentSize

        maximumIntrinsicHeight = max(maximumIntrinsicHeight, intrinsic.height)
        return CGSize(width: UIView.noIntrinsicMetric, height: maximumIntrinsicHeight)
    }

    @objc fileprivate func deviceOrientationDidChange(_ notification: Notification) {
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let triHorizontalOffset: CGFloat = readableContentGuide.layoutFrame.minX + walkerImageInset

        let bezierPath = UIBezierPath()

        // Top left
        bezierPath.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top right
        bezierPath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Bottom right
        bezierPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - triangleHeight))

        // Triangle base, right
        bezierPath.addLine(to: CGPoint(x: rect.maxX - triHorizontalOffset, y: rect.maxY - triangleHeight))

        // Triangle bottom vertex
        bezierPath.addLine(to: CGPoint(x: rect.maxX - triHorizontalOffset - triangleVertexWidth, y: rect.maxY))

        // Triangle base, left
        bezierPath.addLine(to: CGPoint(x: rect.maxX - triHorizontalOffset - triangleVertexWidth - triangleVertexWidth, y: rect.maxY - triangleHeight))

        // Bottom left
        bezierPath.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - triangleHeight))

        // Top left
        bezierPath.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        bezierPath.close()

        let fillColor = backgroundBarColor
        fillColor.setFill()

        bezierPath.fill()
    }
}
