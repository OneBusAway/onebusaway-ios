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

    /// Whether tapping a stop annotation should open a callout, or open the stop directly.
    var showsStopAnnotationCallouts: Bool { get }
}

class StopAnnotationView: MKAnnotationView {

    // MARK: - Delegate

    /// Setting this recomputes `canShowCallout`, which the delegate has a say in. The delegate is
    /// assigned after `init`, so the value computed there is provisional until this fires.
    public weak var delegate: StopAnnotationDelegate? {
        didSet {
            updateCalloutVisibility()
        }
    }

    // MARK: - View Config Constants

    private let kUseDebugColors = false

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = false
        return label
    }()

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
            labelStack.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 3.5),
            labelStack.widthAnchor.constraint(greaterThanOrEqualTo: self.widthAnchor),
            labelStack.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        ])

        if kUseDebugColors {
            backgroundColor = .red
            titleLabel.backgroundColor = .yellow
        }

        rightCalloutAccessoryView = UIButton.chevronButton

        annotationSize = ThemeMetrics.defaultMapAnnotationSize
        updateCalloutVisibility()

        NotificationCenter.default.addObserver(self, selector: #selector(voiceoverStatusDidChange), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            if self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle {
                self.rebuildIcon()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Annotation View Overrides

    public override func prepareForReuse() {
        super.prepareForReuse()

        labelStack.isHidden = true

        titleLabel.text = nil
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()

        // The delegate's answer can change between displays — it reads a feature flag the user
        // can flip mid-session — and a recycled view still carries the previous one.
        updateCalloutVisibility()

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

    private func strokedText(_ text: String) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "HelveticaNeue-Bold", size: 14) as Any,
            .foregroundColor: UIColor.label
        ]

        attributes[.strokeColor] = UIColor.systemBackground
        attributes[.strokeWidth] = -4.0

        return NSAttributedString(string: text, attributes: attributes)
    }

    private func prepareForDisplay(bookmark: Bookmark, delegate: StopAnnotationDelegate) {
        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData
        image = delegate.iconFactory.buildIcon(for: bookmark.stop, isBookmarked: true, traits: traitCollection)
        titleLabel.attributedText = strokedText(bookmark.name)
        detailCalloutAccessoryView = buildDetailLabel(text: bookmark.stop.subtitle)
    }

    private func prepareForDisplay(stop: Stop, delegate: StopAnnotationDelegate) {
        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData
        image = delegate.iconFactory.buildIcon(for: stop, isBookmarked: delegate.isStopBookmarked(stop), traits: traitCollection)
        if let mapTitle = stop.mapTitle {
            titleLabel.attributedText = strokedText(mapTitle)
        }
        else {
            titleLabel.text = ""
        }

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
        updateCalloutVisibility()
    }

    /// A callout is an intermediate step: tap the annotation to preview the stop, then tap the
    /// callout's chevron to actually open it. Two situations skip it, and `MapViewController`
    /// treats selection itself as the open gesture whenever `canShowCallout` is `false`:
    ///
    /// - VoiceOver, because `MKMapView` callouts are finicky under it.
    /// - The redesigned Stop page, which opens as a sheet over the map. The sheet already lands at
    ///   a half detent showing the same name and routes the callout previewed, so the callout is
    ///   a tap the user has to spend for information they are about to get anyway.
    ///
    /// Both inputs can change while a view sits on the map, so this is re-run on display and
    /// whenever `MapRegionManager` refreshes the annotations it is already showing.
    func updateCalloutVisibility() {
        let delegateAllowsCallouts = delegate?.showsStopAnnotationCallouts ?? true
        canShowCallout = !UIAccessibility.isVoiceOverRunning && delegateAllowsCallouts
    }

    private func rebuildIcon() {
        guard
            let stop = annotation as? Stop,
            let delegate = delegate
        else { return }

        image = delegate.iconFactory.buildIcon(for: stop, isBookmarked: delegate.isStopBookmarked(stop), traits: traitCollection)
    }
}
