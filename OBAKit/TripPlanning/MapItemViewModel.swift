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

/// The exact-coordinate probe the address check runs (`OnDemandProbeController.probeExact`).
/// Public because the public `MapItemViewModel.init` takes one.
public typealias OnDemandCoverageProbe = @MainActor (CLLocationCoordinate2D) async throws -> [OnDemandServiceMatch]

/// Spec 3.7: "Inside X" / "Inside X and N more" / "Outside X" for one point.
struct OnDemandCoverageLine: Equatable {
    let match: OnDemandServiceMatch
    let isInside: Bool
    /// Other services that also contain the point.
    let extraCount: Int

    var serviceName: String { match.service.name }

    var text: String {
        if isInside {
            return extraCount > 0
                ? OnDemandCopy.addressInsideMore(name: serviceName, extra: extraCount)
                : String(format: Strings.onDemandAddressInsideFormat, serviceName)
        }
        return String(format: Strings.onDemandAddressOutsideFormat, serviceName)
    }

    /// The first inside match by the shared sort, else the nearest service
    /// within 5,000 m (ties by the sort), else nil.
    static func line(from matches: [OnDemandServiceMatch]) -> OnDemandCoverageLine? {
        let inside = sortedSoonestUsable(matches.filter { $0.isInside && $0.distanceToArea != nil })
        if let first = inside.first {
            return OnDemandCoverageLine(match: first, isInside: true, extraCount: inside.count - 1)
        }
        let nearby = sortedSoonestUsable(matches.filter(\.isNearby))
        guard let closest = nearby.map({ $0.distanceToArea ?? .infinity }).min(),
              let nearest = nearby.first(where: { $0.distanceToArea == closest }) else {
            return nil
        }
        return OnDemandCoverageLine(match: nearest, isInside: false, extraCount: 0)
    }
}

/// The presentation-dependent half of the map-item screen, injected so the same
/// view model drives both the UIKit floating panel and the SwiftUI sheet.
///
/// Everything else the screen does — opening Maps, dialing a phone number — is
/// app-level and needs no presenter.
@MainActor
public struct MapItemActions {
    public var openWebsite: (URL) -> Void
    public var showNearbyStops: (CLLocationCoordinate2D) -> Void
    public var dismiss: () -> Void
    /// Only the UIKit host uses this — the sheet renders a native `ShareLink` from
    /// `MapItemViewModel.shareURL` instead and passes a no-op here.
    public var share: (URL) -> Void
    /// Opens the zone page the coverage line names (spec 3.7); nil leaves the
    /// line inert.
    public var openOnDemandDetail: ((OnDemandServiceMatch, OnDemandLocationCheck) -> Void)?

    public init(
        openWebsite: @escaping (URL) -> Void,
        showNearbyStops: @escaping (CLLocationCoordinate2D) -> Void,
        dismiss: @escaping () -> Void,
        share: @escaping (URL) -> Void = { _ in },
        openOnDemandDetail: ((OnDemandServiceMatch, OnDemandLocationCheck) -> Void)? = nil
    ) {
        self.openWebsite = openWebsite
        self.showNearbyStops = showNearbyStops
        self.dismiss = dismiss
        self.share = share
        self.openOnDemandDetail = openOnDemandDetail
    }

    /// Reproduces the pre-sheet behavior: an in-app Safari controller and a pushed
    /// `NearbyStopsViewController`, both presented from `presenter`, dismissal via
    /// the modal delegate.
    public static func uiKit(
        presenter: UIViewController,
        delegate: ModalDelegate?,
        application: Application
    ) -> MapItemActions {
        MapItemActions(
            openWebsite: { [weak presenter] url in
                guard let presenter else { return }
                application.viewRouter.present(SFSafariViewController(url: url), from: presenter)
            },
            showNearbyStops: { [weak presenter] coordinate in
                guard let presenter else { return }
                let nearbyStops = NearbyStopsViewController(coordinate: coordinate, application: application)
                application.viewRouter.navigate(to: nearbyStops, from: presenter)
            },
            dismiss: { [weak presenter, weak delegate] in
                guard let presenter else { return }
                delegate?.dismissModalController(presenter)
            },
            share: { [weak presenter] url in
                guard let presenter else { return }
                let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                // iPad support, unchanged from the previous `shareLocation()` body.
                if let popover = activityController.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activityController, animated: true)
            }
        )
    }
}

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

    /// `nil` on surfaces that have no trip-planner destination to hand off to.
    /// Gates `showPlanTripButton`, so those surfaces don't render a button that
    /// does nothing when tapped.
    let planTripHandler: (() -> Void)?

    /// Optional handler for removing a user-dropped pin
    let removePinHandler: (() -> Void)?

    /// Presentation-dependent actions injected at init time
    private let actions: MapItemActions

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

    /// Indicates whether the remove pin button should be shown
    var canRemovePin: Bool {
        removePinHandler != nil
    }

    /// The Look Around scene for the location, if available
    var lookAroundScene: MKLookAroundScene?

    /// Indicates whether Look Around is loading
    var isLoadingLookAround: Bool = false

    /// The on-demand coverage line for this point (spec 3.7); nil while loading,
    /// on failure, or when nothing is within 5 km.
    var coverageLine: OnDemandCoverageLine?

    private let coverageProbe: OnDemandCoverageProbe?

    /// Exposed so tests can await the probe.
    private(set) var coverageTask: Task<Void, Never>?

    /// Initializes a new map item view model.
    ///
    /// - Parameters:
    ///   - mapItem: The map item containing location information
    ///   - application: The OBA application instance
    ///   - actions: Injected actions for presentation-dependent operations
    ///   - removePinHandler: Optional handler called when user wants to remove a dropped pin
    ///   - planTripHandler: Handler called when user wants to plan a trip, or `nil`
    ///     to hide the Plan Trip button entirely
    ///   - coverageProbe: The on-demand address check's exact probe, or `nil`
    ///     when the deployment has no `/api/ondemand` (no line is shown)
    public init(
        mapItem: MKMapItem,
        application: Application,
        actions: MapItemActions,
        removePinHandler: (() -> Void)? = nil,
        planTripHandler: (() -> Void)?,
        coverageProbe: OnDemandCoverageProbe? = nil
    ) {
        self.mapItem = mapItem
        self.application = application
        self.actions = actions
        self.removePinHandler = removePinHandler
        self.planTripHandler = planTripHandler
        self.coverageProbe = coverageProbe

        self.title = mapItem.name ?? ""

        if let address = mapItem.placemark.postalAddress {
            self.formattedAddress = CNPostalAddressFormatter.string(from: address, style: .mailingAddress)
        }

        self.showPlanTripButton = application.features.tripPlanning == .running && planTripHandler != nil
        self.phoneNumber = mapItem.phoneNumber
        self.url = mapItem.url

        if let category = mapItem.pointOfInterestCategory {
            self.pointOfInterestCategory = category.rawValue.replacing("MKPOICategory", with: "")
        }

        Task {
            await fetchLookAroundScene()
        }

        if coverageProbe != nil {
            coverageTask = Task { await loadCoverage() }
        }
    }

    /// Runs the exact-coordinate probe; any failure simply shows no line.
    private func loadCoverage() async {
        guard let coverageProbe else { return }
        let coordinate = mapItem.placemark.coordinate
        do {
            coverageLine = OnDemandCoverageLine.line(from: try await coverageProbe(coordinate))
        } catch {
            coverageLine = nil
        }
    }

    /// Opens the zone detail for the named service with `ProbeSource.point` at this pin.
    func openCoverageDetail() {
        guard let coverageLine, let open = actions.openOnDemandDetail else { return }
        let check = OnDemandLocationCheck(
            source: .point(label: mapItem.name),
            isInside: coverageLine.isInside,
            locality: mapItem.placemark.locality,
            coordinate: mapItem.placemark.coordinate
        )
        open(coverageLine.match, check)
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
        // Same Swift 6.2 boundary issue as MapRegionManager.handleMapFeatureSelection:
        // neither the request nor the scene is Sendable, so hand each across in a box —
        // the request is one-shot and the scene has no other owner until the transfer.
        let requestBox = UncheckedSendableBox(value: request)
        do {
            return try await Task.detached {
                UncheckedSendableBox(value: try await requestBox.value.scene)
            }.value.value
        } catch {
            return nil
        }
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

    /// Opens the location's website through the injected action.
    func openURL() {
        guard let url else { return }
        actions.openWebsite(url)
    }

    /// Shows nearby stops through the injected action.
    func showNearbyStops() {
        actions.showNearbyStops(mapItem.placemark.coordinate)
    }

    /// Plans a trip from/to this location.
    ///
    func planTrip() {
        planTripHandler?()
    }

    /// Removes the user-dropped pin and dismisses the view.
    ///
    /// This is only available when the view model was initialized with a removePinHandler.
    func removePin() {
        removePinHandler?()
    }

    /// Dismisses the view through the injected action.
    func dismissView() {
        actions.dismiss()
    }

    /// The Apple Maps link for this place. Exposed so the SwiftUI sheet can use a
    /// native `ShareLink`; the UIKit path still routes through `shareLocation()`.
    var shareURL: URL? {
        appleMapsShareURL(for: mapItem)
    }

    /// Shares the location through the injected action.
    func shareLocation() {
        guard let shareURL else { return }
        actions.share(shareURL)
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
