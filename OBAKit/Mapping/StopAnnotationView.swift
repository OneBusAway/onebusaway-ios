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

    /// Whether stop pins that would overlap merge into a cluster.
    var clustersStops: Bool { get }

    /// Whether this stop currently has an active alert.
    func hasAlert(for stop: Stop) -> Bool
}

extension StopAnnotationDelegate {
    func hasAlert(for stop: Stop) -> Bool {
        return false
    }
}

/// A stop or bookmark pin. It shows no callout: selecting it opens the stop.
class StopAnnotationView: MKAnnotationView {

    // MARK: - Delegate

    public weak var delegate: StopAnnotationDelegate?

    // MARK: - View Config Constants

    private let kUseDebugColors = false

    enum LabelTypography {
        static let basePointSize: CGFloat = 14.0
        static let minimumPointSize: CGFloat = 11.0
        static let maximumPointSize: CGFloat = 22.0
        static let widthMultiplier: CGFloat = 3.5
        static let maxLines: Int = 2
        static let strokeWidth: CGFloat = -4.0
    }

    // MARK: - Subviews

    let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.textAlignment = .center
        label.numberOfLines = LabelTypography.maxLines
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
            labelStack.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: LabelTypography.widthMultiplier),
            labelStack.widthAnchor.constraint(greaterThanOrEqualTo: self.widthAnchor),
            labelStack.centerXAnchor.constraint(equalTo: self.centerXAnchor)
        ])

        if kUseDebugColors {
            backgroundColor = .red
            titleLabel.backgroundColor = .yellow
        }

        annotationSize = ThemeMetrics.defaultMapAnnotationSize

        isAccessibilityElement = true
        accessibilityTraits = .button

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            if self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle {
                self.rebuildIcon()
            }
        }

        // Attributed stroke bakes the font in; rebuild when Dynamic Type changes.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, previousTraitCollection: UITraitCollection) in
            if self.traitCollection.preferredContentSizeCategory != previousTraitCollection.preferredContentSizeCategory {
                self.updateTitleLabel()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Annotation View Overrides

    public override func prepareForReuse() {
        super.prepareForReuse()

        labelStack.isHidden = true
        clusteringIdentifier = nil
        hasAlert = false
        titleLabel.text = nil
        accessibilityLabel = nil
        accessibilityValue = nil
    }

    public override func prepareForDisplay() {
        super.prepareForDisplay()
        applyPresentation()
    }

    /// Sets the icon before MapKit shows the view. `prepareForDisplay` can run
    /// a frame later; leaving `image` nil for that frame is the default-pin flash.
    func applyPresentation() {
        clusteringIdentifier = delegate?.clustersStops == true ? StopCluster.clusteringIdentifier : nil

        guard let delegate else { return }

        if let bookmark = annotation as? Bookmark {
            prepareForDisplay(bookmark: bookmark, delegate: delegate)
        } else if let stop = annotation as? Stop {
            prepareForDisplay(stop: stop, delegate: delegate)
        }
    }

    // MARK: - Annotation Rendering

    var maxLabelWidth: CGFloat {
        let pinWidth = bounds.width > 0 ? bounds.width : ThemeMetrics.defaultMapAnnotationSize
        return pinWidth * LabelTypography.widthMultiplier
    }

    func strokedText(_ text: String, compatibleWith traits: UITraitCollection? = nil) -> NSAttributedString {
        let activeTraits = traits ?? traitCollection
        let font = scaledLabelFont(for: text, compatibleWith: activeTraits)
        return NSAttributedString(string: text, attributes: Self.strokedAttributes(font: font))
    }

    private static func strokedAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: UIColor.label,
            .strokeColor: UIColor.systemBackground,
            .strokeWidth: LabelTypography.strokeWidth
        ]
    }

    func scaledLabelFont(for text: String, compatibleWith traits: UITraitCollection) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: LabelTypography.basePointSize, weight: .bold)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: baseFont,
            maximumPointSize: LabelTypography.maximumPointSize,
            compatibleWith: traits
        )
        let clamped = scaled.pointSize < LabelTypography.minimumPointSize
            ? baseFont.withSize(LabelTypography.minimumPointSize)
            : scaled

        return fittingFont(
            for: text,
            startingFrom: clamped,
            maxWidth: maxLabelWidth,
            maxLines: LabelTypography.maxLines
        )
    }

    private func fittingFont(for text: String, startingFrom font: UIFont, maxWidth: CGFloat, maxLines: Int) -> UIFont {
        guard !text.isEmpty, maxWidth > 0, maxLines > 0 else { return font }

        var currentSize = font.pointSize
        while currentSize > LabelTypography.minimumPointSize {
            let candidate = font.withSize(currentSize)
            if Self.textFits(text, font: candidate, maxWidth: maxWidth, maxLines: maxLines) {
                return candidate
            }
            currentSize = max(LabelTypography.minimumPointSize, currentSize - 0.5)
        }
        return font.withSize(LabelTypography.minimumPointSize)
    }

    private static func textFits(_ text: String, font: UIFont, maxWidth: CGFloat, maxLines: Int) -> Bool {
        let attributed = NSAttributedString(string: text, attributes: strokedAttributes(font: font))
        let measured = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let maxHeight = ceil(font.lineHeight * CGFloat(maxLines)) + 1.0
        return ceil(measured.width) <= maxWidth && ceil(measured.height) <= maxHeight
    }

    private func updateTitleLabel() {
        switch annotation {
        case let bookmark as Bookmark:
            titleLabel.attributedText = strokedText(bookmark.name)
        case let stop as Stop:
            if let mapTitle = stop.mapTitle {
                titleLabel.attributedText = strokedText(mapTitle)
            } else {
                titleLabel.attributedText = nil
                titleLabel.text = ""
            }
        default:
            if let text = titleLabel.attributedText?.string, !text.isEmpty {
                titleLabel.attributedText = strokedText(text)
            }
        }
        titleLabel.invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func prepareForDisplay(bookmark: Bookmark, delegate: StopAnnotationDelegate) {
        hasAlert = delegate.hasAlert(for: bookmark.stop)
        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData
        image = delegate.iconFactory.buildIcon(for: bookmark.stop, isBookmarked: true, traits: traitCollection)
        titleLabel.attributedText = strokedText(bookmark.name)
        accessibilityLabel = Self.accessibilityLabel(for: bookmark)
        accessibilityValue = alertState
    }

    private func prepareForDisplay(stop: Stop, delegate: StopAnnotationDelegate) {
        hasAlert = delegate.hasAlert(for: stop)
        labelStack.isHidden = delegate.shouldHideExtraStopAnnotationData
        image = delegate.iconFactory.buildIcon(for: stop, isBookmarked: delegate.isStopBookmarked(stop), traits: traitCollection)
        if let mapTitle = stop.mapTitle {
            titleLabel.attributedText = strokedText(mapTitle)
        }
        else {
            titleLabel.attributedText = nil
            titleLabel.text = ""
        }
        accessibilityLabel = Self.accessibilityLabel(for: stop)
        accessibilityValue = alertState
    }

    // MARK: - Semantics

    /// Human-readable name of the stop or bookmark.
    public var stopName: String? {
        Self.stopName(for: annotation)
    }

    /// Extract human-readable stop or bookmark name.
    public static func stopName(for annotation: MKAnnotation?) -> String? {
        switch annotation {
        case let stop as Stop:
            return stop.name
        case let bookmark as Bookmark:
            return !bookmark.name.isEmpty ? bookmark.name : bookmark.stop.name
        default:
            return nil
        }
    }

    /// Route context for the stop (direction and routes served).
    public var routeContext: String? {
        Self.routeContext(for: annotation)
    }

    /// Extract route context for an annotation.
    public static func routeContext(for annotation: MKAnnotation?) -> String? {
        let stop: Stop?
        switch annotation {
        case let s as Stop:
            stop = s
        case let b as Bookmark:
            stop = b.stop
        default:
            stop = nil
        }
        guard let stop else { return nil }

        var parts: [String] = []
        if let direction = Formatters.directionString(stop.direction) {
            parts.append(direction)
        }
        if let routes = Formatters.formattedRoutes(stop.routes) {
            parts.append(routes)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// Whether this stop currently has an active alert.
    public var hasAlert: Bool = false {
        didSet {
            accessibilityValue = alertState
        }
    }

    /// Localized alert state description when an alert is active, or nil.
    public var alertState: String? {
        Self.alertState(hasAlert: hasAlert)
    }

    public static func alertState(hasAlert: Bool) -> String? {
        hasAlert ? Strings.serviceAlert : nil
    }

    /// VoiceOver hint for activating this stop annotation.
    public static var accessibilityHint: String {
        OBALoc(
            "map_controller.stop_annotation.accessibility_hint",
            value: "Shows departures for this stop.",
            comment: "VoiceOver hint for a map stop pin. Activating it opens the stop's departures."
        )
    }

    // MARK: - Appearance

    /// Sets the size of the receiver, which in turn configures its bounds and the frame of its contents.
    public var annotationSize: CGFloat {
        get { return bounds.size.width }
        set {
            bounds = CGRect(x: 0, y: 0, width: newValue, height: newValue)
            frame = frame.integral
            if titleLabel.attributedText != nil {
                updateTitleLabel()
            }
        }
    }

    // MARK: - Accessibility

    override var isAccessibilityElement: Bool {
        get { true }
        set { super.isAccessibilityElement = newValue }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { super.accessibilityTraits.union(.button) }
        set { super.accessibilityTraits = newValue }
    }

    override var accessibilityHint: String? {
        get {
            guard annotation is Stop || annotation is Bookmark else {
                return super.accessibilityHint
            }
            return Self.accessibilityHint
        }
        set {
            super.accessibilityHint = newValue
        }
    }

    override var accessibilityLabel: String? {
        get {
            Self.accessibilityLabel(for: annotation) ?? super.accessibilityLabel
        }

        set {
            super.accessibilityLabel = newValue
        }
    }

    override var accessibilityValue: String? {
        get {
            alertState
        }
        set {
            super.accessibilityValue = newValue
        }
    }

    override func accessibilityActivate() -> Bool {
        guard let mapView = findMapView() else { return false }
        if let annotation = annotation {
            mapView.selectAnnotation(annotation, animated: true)
            return true
        }
        return false
    }

    private func findMapView() -> MKMapView? {
        var view: UIView? = self.superview
        while let current = view {
            if let map = current as? MKMapView {
                return map
            }
            view = current.superview
        }
        return nil
    }

    /// Bookmarks share this view with stops, and used to fall through to `nil` —
    /// an unlabelled pin. They now read as the stop does, led by the bookmark's
    /// own name when the rider gave it one.
    static func accessibilityLabel(for annotation: MKAnnotation?) -> String? {
        switch annotation {
        case let stop as Stop:
            return Formatters.formattedAccessibilityLabel(stop: stop)
        case let bookmark as Bookmark:
            return Formatters.formattedAccessibilityLabel(stop: bookmark.stop, bookmarkName: bookmark.name)
        default:
            return nil
        }
    }

    private func rebuildIcon() {
        guard
            let stop = annotation as? Stop,
            let delegate = delegate
        else { return }

        image = delegate.iconFactory.buildIcon(for: stop, isBookmarked: delegate.isStopBookmarked(stop), traits: traitCollection)
    }
}
