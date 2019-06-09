//
//  StopAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/1/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import MapKit

public class StopAnnotationView: MKAnnotationView {

    // MARK: - View Config Constants

    private let wrapperSize: CGFloat = 30.0
    private let imageSize: CGFloat = 20.0

    // MARK: - Subviews

    private let titleLabel = StopAnnotationView.buildLabel()
    private let subtitleLabel = StopAnnotationView.buildLabel()

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 0)
        label.layer.shadowOpacity = 1.0
        label.layer.shadowRadius = 4.0
        label.backgroundColor = UIColor(white: 1.0, alpha: 0.25)
        return label
    }

    private lazy var labelStack: UIStackView = {
        let stack = UIStackView.verticalStack(arangedSubviews: [titleLabel, subtitleLabel])
        return stack
    }()

    private let kUseDebugColors = false

    private lazy var transportWrapper: RoundedShadowView = {
        let wrapper = RoundedShadowView.autolayoutNew()
        wrapper.addSubview(transportImageView)
        return wrapper
    }()

    private let transportImageView: UIImageView = {
        let img = UIImageView.autolayoutNew()
        img.contentMode = .scaleAspectFit
        img.clipsToBounds = true

        return img
    }()

    private lazy var directionalArrowView = TriangleShadowView(frame: .zero)

    // MARK: - Init

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        addSubview(transportWrapper)
        addSubview(directionalArrowView)
        addSubview(labelStack)

        transportWrapper.cornerRadius = 8.0

        NSLayoutConstraint.activate([
            transportWrapper.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            transportWrapper.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            transportWrapper.heightAnchor.constraint(equalToConstant: wrapperSize),
            transportWrapper.widthAnchor.constraint(equalToConstant: wrapperSize),
            transportImageView.widthAnchor.constraint(equalToConstant: imageSize),
            transportImageView.heightAnchor.constraint(equalToConstant: imageSize),
            transportImageView.centerXAnchor.constraint(equalTo: transportWrapper.centerXAnchor),
            transportImageView.centerYAnchor.constraint(equalTo: transportWrapper.centerYAnchor),
            labelStack.topAnchor.constraint(equalTo: self.bottomAnchor),
            labelStack.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 2.0),
            labelStack.widthAnchor.constraint(greaterThanOrEqualTo: self.widthAnchor),
            labelStack.centerXAnchor.constraint(equalTo: self.centerXAnchor)
            ])

        if kUseDebugColors {
            backgroundColor = .red
            transportWrapper.backgroundColor = .green
            transportImageView.backgroundColor = .magenta
            directionalArrowView.backgroundColor = .blue
            titleLabel.backgroundColor = .yellow
            subtitleLabel.backgroundColor = .orange
        }

        let rightCalloutButton = UIButton(type: .detailDisclosure)
        rightCalloutButton.setImage(Icons.chevron, for: .normal)
        rightCalloutAccessoryView = rightCalloutButton
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Annotation View Overrides

    public override func prepareForReuse() {
        super.prepareForReuse()

        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()

        guard let stop = annotation as? Stop else { return }

        transportImageView.image = Icons.transportIcon(from: stop.prioritizedRouteTypeForDisplay)
        titleLabel.attributedText = buildAttributedLabelText(text: stop.mapTitle)
        subtitleLabel.attributedText = buildAttributedLabelText(text: stop.mapSubtitle)

        transportWrapper.fillColor = fillColor
        directionalArrowView.fillColor = fillColor

        transportWrapper.tintColor = tintColor
    }

    override public var annotation: MKAnnotation? {
        didSet {
            guard let annotation = annotation as? Stop else { return }

            if let direction = annotation.direction {
                let angle = rotationAngle(from: direction)
                directionalArrowView.transform = CGAffineTransform(rotationAngle: angle)
                directionalArrowView.isHidden = false
            }
            else {
                directionalArrowView.isHidden = true
            }
        }
    }

    // MARK: - Private Helpers

    private func buildAttributedLabelText(text: String?) -> NSAttributedString? {
        guard let text = text else {
            return nil
        }

        let strokeTextAttributes: [NSAttributedString.Key: Any] = [
            .strokeColor: UIColor.white,
            .foregroundColor: mapTextColor,
            .strokeWidth: -2.0,
            .font: mapTextFont
        ]

        return NSAttributedString(string: text, attributes: strokeTextAttributes)
    }

    private func rotationAngle(from direction: String) -> CGFloat {
        switch direction {
        case "NE": return .pi * 0.25
        case "E":  return .pi * 0.5
        case "SE": return .pi * 0.75
        case "S":  return .pi
        case "SW": return .pi * 1.25
        case "W":  return .pi * 1.5
        case "NW": return .pi * 1.75
        case "N":  fallthrough // swiftlint:disable:this no_fallthrough_only
        default:   return 0
        }
    }

    // MARK: - UIAppearance Proxies

    /// Fill color for this annotation view and its directional arrow.
    @objc dynamic var fillColor: UIColor {
        get { return _fillColor }
        set { _fillColor = newValue }
    }
    private var _fillColor: UIColor!

    /// UIAppearance proxy-compatible version of `canShowCallout`.
    @objc dynamic var showsCallout: Bool {
        get { return canShowCallout }
        set { canShowCallout = newValue }
    }

    /// Sets the size of the receiver, which in turn configures its bounds and the frame of its contents.
    @objc dynamic var annotationSize: CGFloat {
        get { return bounds.size.width }
        set {
            bounds = CGRect(x: 0, y: 0, width: newValue, height: newValue)
            frame = frame.integral
            directionalArrowView.frame = bounds
        }
    }

    /// Foreground color for text written directly onto the map as part of this annotation view.
    @objc dynamic var mapTextColor: UIColor {
        get { return _mapTextColor }
        set { _mapTextColor = newValue }
    }
    private var _mapTextColor: UIColor!

    /// Font for text written directly onto the map as part of this annotation view.
    @objc dynamic var mapTextFont: UIFont {
        get { return _mapTextFont }
        set { _mapTextFont = newValue }
    }
    private var _mapTextFont: UIFont!
}
