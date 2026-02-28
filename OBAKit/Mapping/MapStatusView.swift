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

/// A compact floating pill that displays location authorization status or zoom-in prompts.
///
/// Place this centered horizontally below the safe area top. When there is no status message
/// to display, the pill hides entirely — it no longer doubles as a status bar backdrop.
class MapStatusView: UIView {
    enum LocationState {
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

    // MARK: - UI Elements

    private var visualEffectView: UIVisualEffectView!
    private var stackView: UIStackView!
    private var iconView: UIImageView!
    private var detailLabel: UILabel!

    // MARK: - Layout Constants

    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 18
        static let shadowBlur: CGFloat = 4
        static let shadowOpacity: Float = 0.15
        static let maxWidthRatio: CGFloat = 0.85
    }

    // MARK: - Large Content Properties

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
        // Icon
        iconView = UIImageView.autolayoutNew()
        iconView.tintColor = ThemeColors.shared.brand

        // Label
        detailLabel = UILabel.autolayoutNew()
        detailLabel.font = .preferredFont(forTextStyle: .headline)
        detailLabel.textColor = ThemeColors.shared.brand
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Stack
        stackView = UIStackView(arrangedSubviews: [iconView, detailLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.axis = .horizontal
        stackView.spacing = 8

        // Blur pill
        visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.layer.cornerRadius = Layout.cornerRadius
        visualEffectView.layer.masksToBounds = true
        visualEffectView.contentView.addSubview(stackView)

        addSubview(visualEffectView)

        // Shadow on the outer view for the floating effect
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = Layout.shadowBlur
        layer.shadowOpacity = Layout.shadowOpacity

        NSLayoutConstraint.activate([
            // Stack inside the blur pill with padding
            stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: Layout.verticalPadding),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -Layout.verticalPadding),
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: Layout.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -Layout.horizontalPadding),

            // Blur pill pinned to self edges — self is the pill
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Adapt shadow for dark mode
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == .dark ? 0 : Layout.shadowOpacity
        }
    }

    override var intrinsicContentSize: CGSize {
        let stackSize = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(
            width: stackSize.width + Layout.horizontalPadding * 2,
            height: stackSize.height + Layout.verticalPadding * 2
        )
    }

    // MARK: - State Changes

    func state(for service: LocationService) -> LocationState {
        return .init(
            service.authorizationStatus,
            isImprecise: service.accuracyAuthorization == .reducedAccuracy
        )
    }

    func configure(with service: LocationService) {
        self.configure(for: state(for: service), zoomInStatus: false)
    }

    func configure(for state: LocationState, zoomInStatus: Bool) {
        var shouldHide: Bool
        var setImage: UIImage?
        var setLargeImage: UIImage?
        var setLabel: String?

        switch state {
        case .locationServicesUnavailable, .locationServicesOff, .notDetermined:
            shouldHide = false
            setImage = UIImage(systemName: "location.slash")
            setLargeImage = UIImage(systemName: "location.slash.fill")
            setLabel = OBALoc("map_status_view.location_services_unavailable", value: "Location services unavailable", comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their location")
        case .impreciseLocation:
            shouldHide = false
            setImage = UIImage(systemName: "location.circle")
            setLargeImage = UIImage(systemName: "location.circle.fill")
            setLabel = OBALoc("map_status_view.precise_location_unavailable", value: "Precise location unavailable", comment: "Displayed in the map status view at the top of the map when the user has declined to give the app access to their precise location")
        case .locationServicesOn:
            shouldHide = true
        }

        if zoomInStatus {
            shouldHide = false
            setImage = UIImage(systemName: "plus.magnifyingglass")
            setLargeImage = UIImage(systemName: "plus.magnifyingglass")
            setLabel = OBALoc("map_status_view.zoom_in_for_stops", value: "Zoom in for stops", comment: "Displayed in the map status view at the top of the map when the user must zoom in to see stops on the map")
        }

        // Cancel any in-flight animation to prevent a stale completion
        // from toggling isHidden after a newer state change.
        self.layer.removeAllAnimations()

        if !shouldHide {
            self.isHidden = false
        }

        UIView.animate(withDuration: 0.25) {
            self.alpha = shouldHide ? 0 : 1
            self.iconView.image = setImage
            self.detailLabel.text = setLabel
            self.largeContentImage = setLargeImage
            self.invalidateIntrinsicContentSize()
            self.superview?.layoutIfNeeded()
        } completion: { finished in
            // Only hide if the animation completed without being cancelled.
            if finished && shouldHide {
                self.isHidden = true
            }
        }
    }

    /// Provides a call-to-action alert for resolving location authorization issues.
    /// - important: This only returns the title and message (body) of the alert. You have to manually add applicable actions.
    /// - returns: In situations where the user can't modify their location services or location services is
    /// already enabled, this will return `nil`, meaning the user doesn't need to do anything.
    static func alert(for state: LocationState) -> UIAlertController? {
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

#if DEBUG

extension MapStatusView.LocationState: Identifiable, CaseIterable {
    var id: String { return "\(self)"}
}

struct MapStatusView_Previews: PreviewProvider {
    static func makeStatusView(for state: MapStatusView.LocationState) -> MapStatusView {
        let v = MapStatusView()
        v.configure(for: state, zoomInStatus: false)
        return v
    }

    static var previews: some View {
        ForEach(MapStatusView.LocationState.allCases) { state in
            UIViewPreview {
                makeStatusView(for: state)
            }
            .previewLayout(.fixed(width: 375, height: 64))
            .previewDisplayName(state.id)
        }
    }
}

#endif
