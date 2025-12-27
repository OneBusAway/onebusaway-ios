//
//  MapItemViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Contacts
import SafariServices
import OBAKitCore

/// A view model that manages the data and business logic for displaying map item information.
///
/// This view model extracts and formats data from an `MKMapItem` and handles user interactions
/// such as opening the location in Maps, making phone calls, opening URLs, and navigating to
/// nearby stops. It's designed to work with SwiftUI views using the `@Observable` macro.
///
/// - Note: This class is marked with `@MainActor` to ensure all UI-related operations run on the main thread.
@MainActor
@Observable
public class MapItemViewModel {
    /// The map item containing the location data
    let mapItem: MKMapItem

    /// The OBA application instance for accessing services and navigation
    let application: Application

    let planTripHandler: () -> Void

    /// Delegate for handling modal dismissal
    weak var delegate: ModalDelegate?

    /// The presenting view controller for navigation actions
    private weak var presentingViewController: UIViewController?

    /// The name/title of the location
    var title: String

    /// The formatted postal address of the location, if available
    var formattedAddress: String?

    /// The phone number of the location, if available
    var phoneNumber: String?

    /// The website URL of the location, if available
    var url: URL?

    /// The point of interest category, if available
    var pointOfInterestCategory: String?

    /// Controls whether the "Plan a trip" button is visible
    var showPlanTripButton: Bool = false

    /// Indicates whether there is any content to display in the "About" section.
    var hasAboutContent: Bool {
        formattedAddress != nil || phoneNumber != nil || url != nil
    }

    /// The Look Around scene for the location, if available
    var lookAroundScene: MKLookAroundScene?

    /// Indicates whether Look Around is loading
    var isLoadingLookAround: Bool = false

    /// Initializes a new map item view model.
    ///
    /// - Parameters:
    ///   - mapItem: The map item containing location information
    ///   - application: The OBA application instance
    ///   - delegate: Optional delegate for handling modal dismissal
    public init(mapItem: MKMapItem, application: Application, delegate: ModalDelegate?, planTripHandler: @escaping () -> Void) {
        self.mapItem = mapItem
        self.application = application
        self.delegate = delegate
        self.planTripHandler = planTripHandler

        self.title = mapItem.name ?? ""

        if let address = mapItem.placemark.postalAddress {
            self.formattedAddress = CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
        }

        self.showPlanTripButton = application.features.tripPlanning == .running
        self.phoneNumber = mapItem.phoneNumber
        self.url = mapItem.url

        if let category = mapItem.pointOfInterestCategory {
            self.pointOfInterestCategory = category.rawValue.replacing("MKPOICategory", with: "")
        }

        Task {
            await fetchLookAroundScene()
        }
    }

    /// Fetches the Look Around scene for the map item's location,
    /// falling back to a coordinate-based request if needed.
    private func fetchLookAroundScene() async {
        isLoadingLookAround = true
        defer { isLoadingLookAround = false }

        // LookAround using the mapItem anchor
        if let scene = await fetchScene(using: MKLookAroundSceneRequest(mapItem: mapItem)) {
            self.lookAroundScene = scene
            return
        }

        // Fallback: LookAround using raw coordinates
        let coord = mapItem.placemark.coordinate
        if let scene = await fetchScene(using: MKLookAroundSceneRequest(coordinate: coord)) {
            self.lookAroundScene = scene
            return
        }

        // Nothing available anywhere near this location
        self.lookAroundScene = nil
    }

    /// Helper: attempts to load a scene, returns nil on failure
    private func fetchScene(using request: MKLookAroundSceneRequest) async -> MKLookAroundScene? {
        do {
            return try await request.scene
        } catch {
            return nil
        }
    }

    /// Sets the presenting view controller for navigation actions.
    ///
    /// This must be called before any navigation actions (like showing nearby stops or opening URLs)
    /// to ensure proper view controller presentation.
    ///
    /// - Parameter viewController: The view controller that will present navigation actions
    func setPresentingViewController(_ viewController: UIViewController) {
        self.presentingViewController = viewController
    }

    /// Opens the location in the Maps app.
    ///
    /// This launches the system Maps application and displays the location.
    func openInMaps() {
        mapItem.openInMaps(launchOptions: nil)
    }

    /// Initiates a phone call to the location's phone number.
    ///
    /// This opens the Phone app with the location's phone number ready to dial.
    /// Does nothing if no phone number is available.
    func callPhoneNumber() {
        guard let phone = phoneNumber, let url = URL(phoneNumber: phone) else { return }
        application.open(url, options: [:], completionHandler: nil)
    }

    /// Opens the location's website in a Safari view controller.
    ///
    /// This presents an in-app Safari browser with the location's website.
    /// Does nothing if no URL is available or if the presenting view controller hasn't been set.
    func openURL() {
        guard let url = url else { return }
        guard let presenter = presentingViewController else { return }
        let safari = SFSafariViewController(url: url)
        application.viewRouter.present(safari, from: presenter)
    }

    /// Navigates to the nearby stops view controller.
    ///
    /// This pushes a new view controller showing transit stops near the location.
    /// Does nothing if the presenting view controller hasn't been set.
    func showNearbyStops() {
        guard let presenter = presentingViewController else { return }
        let nearbyStops = NearbyStopsViewController(
            coordinate: mapItem.placemark.coordinate,
            application: application
        )
        application.viewRouter.navigate(to: nearbyStops, from: presenter)
    }

    /// Plans a trip from/to this location.
    ///
    func planTrip() {
        planTripHandler()
    }

    /// Dismisses the view by calling the delegate's dismissModalController method.
    ///
    /// This properly dismisses the FloatingPanel that contains the MapItemViewController.
    func dismissView() {
        guard let presenter = presentingViewController else { return }
        delegate?.dismissModalController(presenter)
    }

    /// Uses the MapKit Place ID when available to generate a stable "Place Link" URL,
    /// falling back to query + coordinates when the place identity is not available.
    func shareLocation() {
        guard let presenter = presentingViewController else { return }
        guard let url = appleMapsShareURL(for: mapItem) else { return }

        let activityItems: [Any] = [url]
        let activityController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

        // iPad support
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        presenter.present(activityController, animated: true)
    }

    /// Generates an Apple Maps share URL using the Place ID when available,
    /// otherwise falls back to a query + coordinates URL.
    private func appleMapsShareURL(for item: MKMapItem) -> URL? {
        // Best case: stable place identity via MapKit Place ID
        if let rawID = item.identifier?.rawValue {
            var components = URLComponents(string: "https://maps.apple.com/place")
            // Newer Place IDs typically start with "I", legacy AUIDs are numeric
            if rawID.hasPrefix("I") {
                components?.queryItems = [URLQueryItem(name: "place-id", value: rawID)]
            } else {
                components?.queryItems = [URLQueryItem(name: "auid", value: rawID)]
            }
            return components?.url
        }

        // Fallback: query + coordinates
        let coordinate = item.placemark.coordinate
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: item.name ?? "Place"),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)")
        ]
        return components?.url
    }
}
