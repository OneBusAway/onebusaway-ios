//
//  MapStatusView.swift
//  OBAKit
//
//  Created by Alan Chu on 7/9/20.
//

import UIKit
import MapKit
import CoreLocation
import OBAKitCore

/// A view intended to be placed at the top of the screen, above a map view, that displays location information.
/// You shouldn't manually change the visibility of this view. This view plays two roles, blurring the content behind
/// the system status bar and displays location authorization, as needed.
/// On iOS 13+, this will also show icons applicable to the situation.
class MapStatusView: UIView {
    enum State {
        /// The user hasn't picked location services yet.
        case notDetermined

        /// Location services is unavailable system-wide.
        case locationServicesUnavailable

        /// Location services is disabled for this application.
        case locationServicesOff

        /// Location services is enabled for this appliation.
        case locationServicesOn

        /// iOS 14+ Location services is enabled, but is set to imprecise location for this application.
        case impreciseLocation

        init(_ authStatus: CLAuthorizationStatus) {
            // TODO: Handle imprecise locations in iOS 14.
            switch authStatus {
            case .notDetermined:
                self = .notDetermined
            case .restricted:
                self = .locationServicesUnavailable
            case .denied:
                self = .locationServicesOff
            case .authorizedAlways, .authorizedWhenInUse:
                self = .locationServicesOn
            @unknown default:
                self = .locationServicesUnavailable
            }
        }
    }

    // MARK: - UI elements
    private var visualView: UIVisualEffectView!
    private var stackView: UIStackView!
    private var iconView: UIImageView!
    private var detailLabel: UILabel!

    // MARK: Large Content properties

    override var showsLargeContentViewer: Bool {
        get { return true }
        set { _ = newValue }
    }

    override var scalesLargeContentImage: Bool {
        get { return true }
        set { _ = newValue }
    }

    override var largeContentTitle: String? {
        get { detailLabel.text }
        set { _ = newValue }
    }

    // MARK: - Initializers
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        stackView = UIStackView.autolayoutNew()
        stackView.alignment = .center
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillProportionally

        // Make visual view
        iconView = UIImageView.autolayoutNew()
        iconView.tintColor = ThemeColors.shared.brand
        stackView.addArrangedSubview(iconView)

        detailLabel = UILabel.autolayoutNew()
        detailLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.textColor = ThemeColors.shared.brand
        stackView.addArrangedSubview(detailLabel)

        visualView = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
        visualView.translatesAutoresizingMaskIntoConstraints = false
        visualView.contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: visualView.layoutMarginsGuide.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: visualView.readableContentGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: visualView.readableContentGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: visualView.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualView.layoutMarginsGuide.bottomAnchor)
        ])

        self.addSubview(visualView)
        visualView.pinToSuperview(.edges)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let padding = traitCollection.verticalSizeClass == .compact ? ThemeMetrics.compactPadding : ThemeMetrics.padding
        visualView.layoutMargins = UIEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)
    }

    // MARK: - State changes

    func configure(for auth: CLAuthorizationStatus) {
        var setHidden: Bool
        var setImage: UIImage?
        var setLargeImage: UIImage?
        var setLabel: String?

        let state = State(auth)

        switch state {
        case .locationServicesUnavailable, .locationServicesOff, .notDetermined:
            setHidden = false
            if #available(iOS 13.0, *) {
                setImage = UIImage(systemName: "location.slash")!
                setLargeImage = UIImage(systemName: "location.slash.fill")!
            }
            setLabel = "Location services unavailable"
        case .impreciseLocation:
            setHidden = false
            if #available(iOS 13.0, *) {
                setImage = UIImage(systemName: "location.circle")!
                setLargeImage = UIImage(systemName: "location.circle.fill")!
            }
            setLabel = "Precise location unavailable"
        case .locationServicesOn:
            setHidden = true
        }

        UIView.animate(withDuration: 0.25) {
            self.stackView.isHidden = setHidden
            self.iconView.image = setImage
            self.detailLabel.text = setLabel

            if #available(iOS 13.0, *) {
                self.largeContentImage = setLargeImage
            }

            self.layoutIfNeeded()
        }
    }

    /// Provides a call-to-action alert for resolving location authorization issues.
    /// - important: This only returns the title and message (body) of the alert. You have to manually add applicable actions.
    /// - returns: In situations where the user can't modify their location services or location services is
    /// already enabled, this will return `nil`, meaning the user doesn't need to do anything.
    static func alert(for state: State) -> UIAlertController? {
        let title: String
        let message: String

        switch state {
        case .locationServicesUnavailable, .locationServicesOn:
            return nil
        case .locationServicesOff, .notDetermined:
            title = OBALoc("locationservices_alert_off.title", value: "OneBusAway works best with your location.", comment: "")
            message = OBALoc("locationservices_alert_off.message", value: "You'll get to see where you are on the map and see nearby stops, making it easier to get where you need to go.", comment: "")
        case .impreciseLocation:
            title = OBALoc("locationservices_alert_imprecise.title", value: "OneBusAway works best with your precise location", comment: "")
            message = OBALoc("locationservices_alert_imprecise.message", value: "You'll get to see where you are on the map and see nearby stops, making it easier to get where you need to go.", comment: "")
        }

        return UIAlertController(title: title, message: message, preferredStyle: .alert)
    }
}
