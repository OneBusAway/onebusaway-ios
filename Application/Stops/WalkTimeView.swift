//
//  WalkTimeView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/17/19.
//

import UIKit
import CoreLocation

/// Designed to slot into an `AloeStackView`, `UITableView`, or `UICollectionView` to give the user
/// an indication of which vehicles they will be able to catch from the stop they are viewing.
class WalkTimeView: UIView {

    private let kUseDebugColors = false

    private let label: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var triangleHeight = ThemeMetrics.padding
    private lazy var triangleVertexWidth = 1.5 * triangleHeight

    private let walkerImageInset: CGFloat = 26.0

    private let walkerImageView: UIImageView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.image = Icons.walkTransport
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        return imageView
    }()

    public var formatters: Formatters!

    /// The font used on the label.
    @objc public dynamic var font: UIFont {
        set { label.font = newValue }
        get { return label.font }
    }

    /// The text color used on the label.
    @objc public dynamic var textColor: UIColor {
        set { label.textColor = newValue }
        get { return label.textColor }
    }

    /// Background color of the background bar and triangle views.
    @objc public dynamic var backgroundBarColor: UIColor {
        set { _backgroundBarColor = newValue }
        get { return _backgroundBarColor }
    }
    private var _backgroundBarColor: UIColor = UIColor.green

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
            walkerImageView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -walkerImageInset - 5.0),
            walkerImageView.heightAnchor.constraint(equalToConstant: 16.0),
            walkerImageView.widthAnchor.constraint(equalToConstant: 16.0),

            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -triangleHeight),
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: walkerImageView.leadingAnchor, constant: -ThemeMetrics.compactPadding)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func set(distance: CLLocationDistance, timeToWalk: TimeInterval) {
        // bail out if the distance is 40 meters or less. Just don't show anything because
        // it suggests the user is essentially at the stop and showing '100 feet arriving in 1
        // min' looks weird.
        guard distance > 40 else {
            label.text = nil
            return
        }

        let distanceString = formatters.distanceFormatter.string(fromDistance: distance)

        if let timeString = formatters.positionalTimeFormatter.string(from: timeToWalk) {
            let arrivalTime = formatters.timeFormatter.string(from: Date().addingTimeInterval(timeToWalk))
            let fmt = NSLocalizedString("walk_time_view.distance_time_fmt", value: "%@, %@: arriving at %@", comment: "Format string with placeholders for distance from stop, walking time to stop, and predicted arrival time. e.g. 1.2 miles, 17m: arriving at 09:41 A.M.")
            label.text = String(format: fmt, distanceString, timeString, arrivalTime)
        }
        else {
            label.text = distanceString
        }
    }

    public override var intrinsicContentSize: CGSize {
        let intrinsic = super.intrinsicContentSize
        if intrinsic.height > 0 {
            return intrinsic
        }
        else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 4.0)
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let triHorizontalOffset: CGFloat = walkerImageView.center.y + walkerImageInset

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
