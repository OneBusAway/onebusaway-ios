//
//  StopAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/1/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import MapKit

extension Stop: MKAnnotation {
    public var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }

    public var title: String? {
        return Formatters.formattedTitle(stop: self)
    }

    public var subtitle: String? {
        return Formatters.formattedRoutes(routes)
    }

    public var mapTitle: String? {
        return routes.map { $0.shortName }.localizedCaseInsensitiveSort().prefix(3).joined(separator: ", ")
    }

    public var mapSubtitle: String? {
        return Formatters.adjectiveFormOfCardinalDirection(direction)
    }
}

public class StopAnnotationView: MKAnnotationView {

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

    private var _theme: Theme!
    @objc dynamic var theme: Theme {
        get { return _theme }
        set {
            if _theme != newValue {
                _theme = newValue
                configureUI()
            }
        }
    }

    private let wrapperSize: CGFloat = 30.0
    private let imageSize: CGFloat = 20.0

    private func configureUI() {
        bounds = CGRect(x: 0, y: 0, width: ThemeMetrics.defaultMapAnnotationSize, height: ThemeMetrics.defaultMapAnnotationSize)
        frame = frame.integral

        directionalArrowView.frame = bounds

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

        canShowCallout = theme.behaviors.mapShowsCallouts
    }

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        addSubview(transportWrapper)
        addSubview(directionalArrowView)
        addSubview(labelStack)

        let rightCalloutButton = UIButton(type: .detailDisclosure)
        rightCalloutButton.setImage(Icons.chevron, for: .normal)
        rightCalloutAccessoryView = rightCalloutButton
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()

        if let stop = annotation as? Stop {
            transportImageView.image = Icons.transportIcon(from: stop.prioritizedRouteTypeForDisplay)
            titleLabel.attributedText = buildAttributedLabelText(text: stop.mapTitle)
            subtitleLabel.attributedText = buildAttributedLabelText(text: stop.mapSubtitle)

            let fillColor = (annotation as? Stop)?.routes.first?.color ?? theme.colors.primary
            transportWrapper.fillColor = fillColor
            directionalArrowView.fillColor = fillColor

            transportWrapper.tintColor = theme.colors.stopAnnotationIcon
        }
    }

    override public var annotation: MKAnnotation? {
        didSet {
            guard let annotation = annotation as? Stop else {
                return
            }

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

    private func buildAttributedLabelText(text: String?) -> NSAttributedString? {
        guard let text = text else {
            return nil
        }

        let strokeTextAttributes: [NSAttributedString.Key: Any] = [
            .strokeColor: UIColor.white,
            .foregroundColor: theme.colors.mapText,
            .strokeWidth: -2.0,
            .font: theme.fonts.mapAnnotation
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
}
