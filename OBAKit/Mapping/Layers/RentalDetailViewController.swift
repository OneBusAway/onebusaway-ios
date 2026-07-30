//
//  RentalDetailViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import OTPKit
import SwiftUI
import UIKit

/// Actions a rental detail surface can trigger. Implemented by `MapViewController`,
/// which owns navigation and the trip planner.
@MainActor protocol RentalLayerActionsDelegate: AnyObject {
    /// "Plan a trip using this bike": open the trip planner with a via point at
    /// the vehicle's coordinate and a rental mode preselected.
    func rentalLayer(planTripUsing rental: VehicleRental)

    /// Open a rental deep link, falling back to the operator's web page when the
    /// primary URI fails to open (e.g. custom scheme with no app installed).
    func rentalLayer(open url: URL, webFallback: URL?)
}

// MARK: - Detail Sheet

/// Bottom sheet for a single rental vehicle or station — same visual family as
/// the stop page, so vehicles and stops behave identically.
final class RentalDetailViewController: UIHostingController<RentalDetailView> {

    init(
        rental: VehicleRental,
        fetchedAt: Date?,
        staleAfter: Duration?,
        userLocation: CLLocation? = nil,
        actionsDelegate: RentalLayerActionsDelegate? = nil
    ) {
        weak var delegate = actionsDelegate
        super.init(rootView: RentalDetailView(
            rental: rental,
            fetchedAt: fetchedAt,
            staleAfter: staleAfter,
            userLocation: userLocation,
            onPlanTrip: { delegate?.rentalLayer(planTripUsing: $0) },
            onOpenURL: { delegate?.rentalLayer(open: $0, webFallback: $1) }
        ))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RentalDetailView: View {
    let rental: VehicleRental
    let fetchedAt: Date?
    /// The layer's declared trust window; past it, the footer flags the data as stale.
    let staleAfter: Duration?
    let userLocation: CLLocation?
    var onPlanTrip: (VehicleRental) -> Void
    var onOpenURL: (URL, URL?) -> Void

    /// Reverse-geocoded on selection — never in bulk. Falls back to a plain
    /// distance string while loading or when geocoding fails.
    @State private var crossStreet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statsRow

            Button {
                onPlanTrip(rental)
            } label: {
                Label(
                    OBALoc("rental_detail.plan_trip", value: "Plan a trip using this bike", comment: "Primary action on the rental vehicle sheet"),
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .rentalPurple))

            if let deepLink = deepLinkURL {
                Button {
                    onOpenURL(deepLink.url, deepLink.webFallback)
                } label: {
                    Text(deepLink.title)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            attributionFooter
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await reverseGeocode() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rental.displayLabel)
                .font(.title2.bold())

            if let subtitle = locationSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !rental.isOperative {
                Text(OBALoc("rental_detail.not_in_service", value: "Not in service", comment: "Shown for a rental vehicle or station that is not operative"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    /// Cross-street (once geocoded) with an estimated walk time; distance-only
    /// until then.
    private var locationSubtitle: String? {
        let walk = walkDescription
        if let crossStreet {
            if let walk {
                return "\(crossStreet) · \(walk)"
            }
            return crossStreet
        }
        return walk
    }

    private var walkDescription: String? {
        RentalFormat.walkTimeText(from: userLocation, to: rental.coordinate)
    }

    @ViewBuilder private var statsRow: some View {
        switch rental {
        case .vehicle(let vehicle):
            HStack(spacing: 20) {
                // Range first: on the launch feed, battery percent is null across
                // the entire fleet while range is populated. Battery only renders
                // when the feed actually provides it.
                if let range = vehicle.fuel?.range {
                    stat(
                        value: RentalFormat.distanceFormatter.string(fromDistance: CLLocationDistance(range)),
                        label: OBALoc("rental_detail.range", value: "Range", comment: "Label for a rental vehicle's estimated remaining range")
                    )
                }
                if let percent = vehicle.fuel?.percent {
                    stat(
                        value: RentalFormat.batteryText(percent),
                        label: OBALoc("rental_detail.battery", value: "Battery", comment: "Label for a rental vehicle's battery charge")
                    )
                }
                if let propulsion = vehicle.vehicleType?.propulsionType {
                    stat(
                        value: Self.propulsionName(propulsion),
                        label: OBALoc("rental_detail.propulsion", value: "Type", comment: "Label for a rental vehicle's propulsion type")
                    )
                }
            }
        case .station(let station):
            HStack(spacing: 20) {
                if let vehicles = station.vehiclesAvailableCount {
                    stat(
                        value: String(vehicles),
                        label: OBALoc("rental_detail.bikes_available", value: "Bikes", comment: "Label for the number of bikes available at a station")
                    )
                }
                if let docks = station.docksAvailableCount {
                    stat(
                        value: String(docks),
                        label: OBALoc("rental_detail.docks_available", value: "Docks", comment: "Label for the number of open docks at a station")
                    )
                }
                if station.allowPickupNow == false {
                    stat(
                        value: OBALoc("rental_detail.no", value: "No", comment: "Value shown when pickup or dropoff is not currently allowed"),
                        label: OBALoc("rental_detail.pickup", value: "Pickup", comment: "Label for whether picking up a vehicle is currently allowed")
                    )
                }
                if station.allowDropoffNow == false {
                    stat(
                        value: OBALoc("rental_detail.no", value: "No", comment: "Value shown when pickup or dropoff is not currently allowed"),
                        label: OBALoc("rental_detail.dropoff", value: "Drop-off", comment: "Label for whether dropping off a vehicle is currently allowed")
                    )
                }
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Deep link: the GBFS iOS URI when present, the operator's web page as
    /// fallback, nothing (the norm on the launch feed) otherwise.
    private var deepLinkURL: (title: String, url: URL, webFallback: URL?)? {
        let operatorName = rental.rentalNetwork?.displayName
        let template = OBALoc("rental_detail.open_in_fmt", value: "Open in %@", comment: "Button opening the rental operator's app or website")
        let webURL = rental.rentalNetwork?.url.flatMap(URL.init(string:))

        if let ios = rental.rentalUris?.ios, let url = URL(string: ios) {
            return (String(format: template, operatorName ?? url.host() ?? "app"), url, webURL)
        }
        if let webURL {
            return (String(format: template, operatorName ?? webURL.host() ?? "web"), webURL, nil)
        }
        return nil
    }

    /// Re-rendered every 30s so a sheet left open keeps telling the truth, and the
    /// layer's declared `staleAfter` window flags data past its trust horizon.
    @ViewBuilder private var attributionFooter: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let freshness = fetchedAt.map {
                String(format: OBALoc("rental_detail.updated_fmt", value: "Updated %@", comment: "Feed freshness line; the argument is a relative time like '12 seconds ago'"),
                       RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: context.date))
            }

            let isStale: Bool = {
                guard let fetchedAt, let staleAfter else { return false }
                return context.date.timeIntervalSince(fetchedAt) > Double(staleAfter.components.seconds)
            }()

            let parts = [rental.rentalNetwork?.displayName, freshness].compactMap { $0 }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            if isStale {
                Text(OBALoc("rental_detail.stale_warning", value: "This data may be out of date.", comment: "Warning shown when rental data is older than the layer's freshness window"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private static func propulsionName(_ raw: String) -> String {
        switch raw.uppercased() {
        case "ELECTRIC", "ELECTRIC_ASSIST":
            return OBALoc("rental_detail.propulsion_electric", value: "Electric", comment: "Rental vehicle propulsion: electric")
        case "HUMAN":
            return OBALoc("rental_detail.propulsion_human", value: "Pedal", comment: "Rental vehicle propulsion: human-powered")
        case "COMBUSTION":
            return OBALoc("rental_detail.propulsion_combustion", value: "Gas", comment: "Rental vehicle propulsion: combustion")
        default:
            return raw.capitalized.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func reverseGeocode() async {
        let location = CLLocation(latitude: rental.coordinate.latitude, longitude: rental.coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        crossStreet = placemark.thoroughfare ?? placemark.name
    }
}

// MARK: - Cluster List Sheet

/// "N vehicles here": dockless vehicles genuinely pile up at corners, and a list
/// is the honest representation — never a forced zoom.
final class RentalClusterListViewController: UIHostingController<RentalClusterListView> {

    init(
        rentals: [VehicleRental],
        fetchedAt: Date?,
        staleAfter: Duration?,
        userLocation: CLLocation? = nil,
        actionsDelegate: RentalLayerActionsDelegate? = nil
    ) {
        weak var delegate = actionsDelegate
        super.init(rootView: RentalClusterListView(
            rentals: rentals,
            fetchedAt: fetchedAt,
            staleAfter: staleAfter,
            userLocation: userLocation,
            onPlanTrip: { delegate?.rentalLayer(planTripUsing: $0) },
            onOpenURL: { delegate?.rentalLayer(open: $0, webFallback: $1) }
        ))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct RentalClusterListView: View {
    let rentals: [VehicleRental]
    let fetchedAt: Date?
    let staleAfter: Duration?
    let userLocation: CLLocation?
    var onPlanTrip: (VehicleRental) -> Void
    var onOpenURL: (URL, URL?) -> Void

    @State private var selectedRental: VehicleRental?

    var body: some View {
        NavigationStack {
            List(rentals) { rental in
                Button {
                    selectedRental = rental
                } label: {
                    row(for: rental)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(String(format: OBALoc("rental_cluster.title_fmt", value: "%d vehicles here", comment: "Title of the sheet listing the members of a rental cluster"), rentals.count))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedRental) { rental in
                RentalDetailView(
                    rental: rental,
                    fetchedAt: fetchedAt,
                    staleAfter: staleAfter,
                    userLocation: userLocation,
                    onPlanTrip: onPlanTrip,
                    onOpenURL: onOpenURL
                )
                .presentationDetents([.medium])
            }
        }
    }

    private func row(for rental: VehicleRental) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: rental))
                .foregroundStyle(Color(uiColor: .rentalPurple))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(rental.displayLabel)
                    .font(.body.weight(.medium))
                if let detail = detailLine(for: rental) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// Range (battery only when the feed provides it) and walk estimate.
    private func detailLine(for rental: VehicleRental) -> String? {
        var parts: [String] = []

        if case .vehicle(let vehicle) = rental {
            if let range = vehicle.fuel?.range {
                parts.append(RentalFormat.distanceFormatter.string(fromDistance: CLLocationDistance(range)))
            }
            if let percent = vehicle.fuel?.percent {
                parts.append(RentalFormat.batteryText(percent))
            }
        }

        if let walkTime = RentalFormat.walkTimeText(from: userLocation, to: rental.coordinate) {
            parts.append(walkTime)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func iconName(for rental: VehicleRental) -> String {
        switch rental {
        case .station:
            return "parkingsign.circle"
        case .vehicle(let vehicle):
            if vehicle.vehicleType?.formFactor?.isScooter == true { return "scooter" }
            return "bicycle"
        }
    }
}
