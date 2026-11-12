//
//  WalkingDirectionsProvider.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation

enum WalkingDirectionsProvider: String, CaseIterable {
    case askEveryTime
    case appleMaps
    case googleMaps

    static let defaultsKey = "walkingDirectionsProvider"

    init(userDefaults: UserDefaults) {
        self = userDefaults.string(forKey: Self.defaultsKey).flatMap(Self.init(rawValue:)) ?? .askEveryTime
    }

    var localizedTitle: String {
        switch self {
        case .askEveryTime:
            return OBALoc("settings_controller.walking_directions.ask", value: "Ask every time", comment: "Walking directions provider option that keeps the maps app chooser")
        case .appleMaps:
            return OBALoc("settings_controller.walking_directions.apple", value: "Apple Maps", comment: "Apple Maps walking directions provider option")
        case .googleMaps:
            return OBALoc("settings_controller.walking_directions.google", value: "Google Maps", comment: "Google Maps walking directions provider option")
        }
    }

    var actionTitle: String {
        switch self {
        case .askEveryTime:
            return OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop")
        case .appleMaps:
            return OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop")
        case .googleMaps:
            return OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop")
        }
    }

    /// Keep the chooser when no preference is set, or when the preferred app
    /// is unavailable. Never change the saved preference during fallback.
    static func options(coordinate: CLLocationCoordinate2D, preferred: Self, googleMapsAvailable: Bool) -> [(provider: Self, url: URL)] {
        var options: [(provider: Self, url: URL)] = []
        if let url = AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate) {
            options.append((.appleMaps, url))
        }
        if googleMapsAvailable, let url = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate) {
            options.append((.googleMaps, url))
        }
        if let preferredOption = options.first(where: { $0.provider == preferred }) {
            return [preferredOption]
        }
        return options
    }

    /// Shared by the legacy and SwiftUI stop pages' More menus.
    static func menuElement(coordinate: CLLocationCoordinate2D?, application: Application, googleMapsAvailable: Bool) -> UIMenuElement {
        let preferred = Self(userDefaults: application.userDefaults)
        let options = coordinate.map { Self.options(coordinate: $0, preferred: preferred, googleMapsAvailable: googleMapsAvailable) } ?? []
        let title = Self.askEveryTime.actionTitle
        let image = UIImage(systemName: "figure.walk")
        guard !options.isEmpty else {
            return UIAction(title: title, image: image, attributes: .disabled) { _ in }
        }
        if preferred != .askEveryTime, let option = options.first, options.count == 1 {
            return UIAction(title: title, image: image) { [weak application] _ in
                application?.open(option.url, options: [:], completionHandler: nil)
            }
        }
        return UIMenu(title: title, image: image, children: options.map { option in
            UIAction(title: option.provider.actionTitle) { [weak application] _ in
                application?.open(option.url, options: [:], completionHandler: nil)
            }
        })
    }
}
