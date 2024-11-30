//
//  StopAnnotationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    // MARK: - Subviews

    private let titleLabel = StopAnnotationView.buildLabel()

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.font = UIFont.mapAnnotationFont
        label.numberOfLines = 2
        return label
    }

    private lazy var labelStack: UIStackView = {
        return UIStackView.verticalStack(arrangedSubviews: [titleLabel])
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
        }

        rightCalloutAccessoryView = UIButton.chevronButton

        annotationSize = ThemeMetrics.defaultMapAnnotationSize
        updateAccessibility()

        NotificationCenter.default.addObserver(self, selector: #selector(voiceoverStatusDidChange), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            if self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle {
                self.rebuildIcon()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Annotation View Overrides

    public override func prepareForReuse() {
        super.prepareForReuse()

        labelStack.isHidden = true

        titleLabel.text = nil
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()

        guard let delegate = delegate else {
            return
        }

        if let bookmark = annotation as? Bookmark {
            prepareForDisplay(bookmark: bookmark, delegate: delegate)
        }
        else if let stop = annotation as? Stop {
            prepareForDisplay(stop: stop, delegate: delegate)
        }
    }

    // MARK: - Annotation Rendering

    private func prepareForDisplay(bookmark: Bookmark, delegate: StopAnnotationDelegate) {
        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData
        image = delegate.iconFactory.buildIcon(for: bookmark.stop, isBookmarked: true, traits: traitCollection)
        titleLabel.text = bookmark.name
        detailCalloutAccessoryView = buildDetailLabel(text: bookmark.stop.subtitle)
    }

    private func prepareForDisplay(stop: Stop, delegate: StopAnnotationDelegate) {
        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData
        image = delegate.iconFactory.buildIcon(for: stop, isBookmarked: delegate.isStopBookmarked(stop), traits: traitCollection)
        titleLabel.text = stop.mapTitle
        detailCalloutAccessoryView = buildDetailLabel(text: stop.subtitle)
    }

    private func buildDetailLabel(text: String?) -> UILabel {
        let detailLabel = UILabel()
        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.numberOfLines = 0
        detailLabel.text = text
        return detailLabel
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

    /// Foreground color for text written directly onto the map as part of this annotation view.
    public var mapTextColor: UIColor = ThemeColors.shared.mapText

    // MARK: - Accessibility

    override var accessibilityLabel: String? {
        get {
            guard let stop = annotation as? Stop else {
                return nil
            }

            return Formatters.formattedAccessibilityLabel(stop: stop)
        }

        set {
            super.accessibilityLabel = newValue
        }
    }

    @objc fileprivate func voiceoverStatusDidChange(_ notification: Notification) {
        updateAccessibility()
    }

    fileprivate func updateAccessibility() {
        // Callouts are finicky when in VoiceOver. When VoiceOver is running,
        // we should skip the callout and push directly to the annotation's destination view.
        canShowCallout = !UIAccessibility.isVoiceOverRunning
    }
    
    private func rebuildIcon() {
        guard
            let stop = annotation as? Stop,
            let delegate = delegate
        else { return }

        image = delegate.iconFactory.buildIcon(for: stop, isBookmarked: delegate.isStopBookmarked(stop), traits: traitCollection)
    }
}
