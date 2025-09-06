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
/// nearby stops. It's designed to work with SwiftUI views using the `ObservableObject` protocol.
///
/// - Note: This class is marked with `@MainActor` to ensure all UI-related operations run on the main thread.
@MainActor
public class MapItemViewModel: ObservableObject {
    /// The map item containing the location data
    private let mapItem: MKMapItem

    /// The OBA application instance for accessing services and navigation
    private let application: Application

    /// Delegate for handling modal dismissal
    private weak var delegate: ModalDelegate?

    /// The presenting view controller for navigation actions
    private weak var presentingViewController: UIViewController?

    /// The name/title of the location
    @Published var title: String

    /// The formatted postal address of the location, if available
    @Published var formattedAddress: String?

    /// The phone number of the location, if available
    @Published var phoneNumber: String?

    /// The website URL of the location, if available
    @Published var url: URL?
    
    /// Controls whether the "Plan a trip" button is visible
    @Published var showPlanTripButton: Bool = false

    /// Indicates whether there is any content to display in the "About" section.
    var hasAboutContent: Bool {
        formattedAddress != nil || phoneNumber != nil || url != nil
    }

    /// The Look Around scene for the location, if available
    @Published var lookAroundScene: MKLookAroundScene?

    /// Indicates whether Look Around is loading
    @Published var isLoadingLookAround: Bool = false

    /// Initializes a new map item view model.
    ///
    /// - Parameters:
    ///   - mapItem: The map item containing location information
    ///   - application: The OBA application instance
    ///   - delegate: Optional delegate for handling modal dismissal
    public init(mapItem: MKMapItem, application: Application, delegate: ModalDelegate?) {
        self.mapItem = mapItem
        self.application = application
        self.delegate = delegate

        self.title = mapItem.name ?? ""

        if let address = mapItem.placemark.postalAddress {
            self.formattedAddress = CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
        }

        self.phoneNumber = mapItem.phoneNumber
        self.url = mapItem.url

        Task {
            await fetchLookAroundScene()
        }
    }

    /// Fetches the Look Around scene for the map item's location
    private func fetchLookAroundScene() async {
        isLoadingLookAround = true
        defer { isLoadingLookAround = false }

        let request = MKLookAroundSceneRequest(mapItem: mapItem)
        do {
            if let scene = try await request.scene {
                self.lookAroundScene = scene
            }
        } catch {
            // Look Around not available for this location
            self.lookAroundScene = nil
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
    /// This will be handled by the hosting view controller.
    /// Does nothing if the presenting view controller hasn't been set.
    func planTrip() {
        // This will be implemented by the hosting view controller
        // For now, it's a placeholder that can be extended
        guard let _ = presentingViewController else { return }
        // TODO: Implement trip planning logic
    }

    /// Dismisses the view by calling the delegate's dismissModalController method.
    ///
    /// This properly dismisses the FloatingPanel that contains the MapItemViewController.
    func dismissView() {
        guard let presenter = presentingViewController else { return }
        delegate?.dismissModalController(presenter)
    }
}
