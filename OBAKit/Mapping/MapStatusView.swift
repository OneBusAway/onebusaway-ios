//
//  MapStatusView.swift
//  OBAKit
//
//  Created by Alan Chu on 7/9/20.
//

import UIKit
import MapKit
import SwiftUI
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

        init(_ authStatus: CLAuthorizationStatus, isImprecise: Bool = false) {
            switch authStatus {
            case .notDetermined:
                self = .notDetermined
            case .restricted:
                self = .locationServicesUnavailable
            case .denied:
                self = .locationServicesOff
            case .authorizedAlways, .authorizedWhenInUse:
                self = isImprecise ? .impreciseLocation : .locationServicesOn
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
    func state(for service: LocationService) -> State {
        if #available(iOS 14, *) {
            return .init(service.authorizationStatus,
                           isImprecise: service.accuracyAuthorization == .reducedAccuracy)
        } else {
            return .init(service.authorizationStatus)
        }
    }

    func configure(with service: LocationService) {
        self.configure(for: state(for: service))
    }

    func configure(for state: State) {
        var setHidden: Bool
        var setImage: UIImage?
        var setLargeImage: UIImage?
        var setLabel: String?

        switch state {
        case .locationServicesUnavailable, .locationServicesOff, .notDetermined:
            setHidden = false
            setImage = UIImage(systemName: "location.slash")!
            setLargeImage = UIImage(systemName: "location.slash.fill")!
            setLabel = OBALoc("map_status_view.location_services_unavailable", value: "Location services unavailable", comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their location")
        case .impreciseLocation:
            setHidden = false
            setImage = UIImage(systemName: "location.circle")!
            setLargeImage = UIImage(systemName: "location.circle.fill")!
            setLabel = OBALoc("map_status_view.precise_location_unavailable", value: "Precise location unavailable", comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their precise location")
        case .locationServicesOn:
            setHidden = true
        }

        UIView.animate(withDuration: 0.25) {
            self.stackView.isHidden = setHidden
            self.iconView.image = setImage
            self.detailLabel.text = setLabel
            self.largeContentImage = setLargeImage

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

// MARK: - Previews

extension MapStatusView.State: Identifiable, CaseIterable {
    var id: String { return "\(self)"}
}

struct MapStatusView_Previews: PreviewProvider {
    static func makeStatusView(for state: MapStatusView.State) -> MapStatusView {
        let v = MapStatusView()
        v.configure(for: state)
        return v
    }

    static var previews: some View {
        ForEach(MapStatusView.State.allCases) { state in
            UIViewPreview {
                makeStatusView(for: state)
            }
            .previewLayout(.fixed(width: 375, height: 64))
            .previewDisplayName(state.id)
        }
    }
}
