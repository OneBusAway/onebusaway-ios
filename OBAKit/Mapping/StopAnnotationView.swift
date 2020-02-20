//
//  StopAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/1/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import MapKit
import OBAKitCore

protocol StopAnnotationDelegate: NSObjectProtocol {
    func isStopBookmarked(_ stop: Stop) -> Bool
    var iconFactory: StopIconFactory { get }
    var shouldHideExtraStopAnnotationData: Bool { get }
}

class StopAnnotationView: MKAnnotationView {

    // MARK: - Delegate
    public weak var delegate: StopAnnotationDelegate?

    // MARK: - View Config Constants

    private let kUseDebugColors = false
    private let wrapperSize: CGFloat = 30.0
    private let imageSize: CGFloat = 20.0

    // MARK: - Subviews

    private let titleLabel = StopAnnotationView.buildLabel()
    private let subtitleLabel = StopAnnotationView.buildLabel()

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = UIFont.mapAnnotationFont
        return label
    }

    private lazy var labelStack: UIStackView = {
        return UIStackView.verticalStack(arrangedSubviews: [titleLabel, subtitleLabel])
    }()

    public var isHidingExtraStopAnnotationData: Bool {
        get {
            labelStack.isHidden
        }
        set {
            labelStack.isHidden = newValue
        }
    }

    // MARK: - Init

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        addSubview(labelStack)

        NSLayoutConstraint.activate([
            labelStack.topAnchor.constraint(equalTo: self.bottomAnchor),
            labelStack.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 2.0),
            labelStack.widthAnchor.constraint(greaterThanOrEqualTo: self.widthAnchor),
            labelStack.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        ])

        if kUseDebugColors {
            backgroundColor = .red
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

        labelStack.isHidden = true

        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()

        guard
            let stop = annotation as? Stop,
            let delegate = delegate
        else { return }

        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData

        let iconFactory = delegate.iconFactory
        image = iconFactory.buildIcon(for: stop, strokeColor: strokeColor, fillColor: fillColor)

        titleLabel.text = stop.mapTitle
        subtitleLabel.text = stop.mapSubtitle
    }

    // MARK: - UIAppearance Proxies

    /// Fill color for this annotation view and its directional arrow.
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
    private var _strokeColor: UIColor = .white

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
        }
    }

    /// Foreground color for text written directly onto the map as part of this annotation view.
    @objc dynamic var mapTextColor: UIColor {
        get { return _mapTextColor }
        set { _mapTextColor = newValue }
    }
    private var _mapTextColor: UIColor = .black
}
