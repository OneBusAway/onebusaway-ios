//
//  RentalMapMarker.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import OTPKit
import SwiftUI

/// A single rental on the SwiftUI panel map. Approximates
/// `RentalAnnotationView`: rental purple when operative, gray when not, a
/// form-factor glyph for free-floating vehicles and an availability count for
/// docked stations.
struct RentalMapMarker: View {
    let rental: VehicleRental
    let showsFuelLabel: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(markerColor)
                .frame(width: 28, height: 28)
                .shadow(radius: 1, y: 1)

            if let count = stationAvailabilityText {
                Text(count)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: glyphName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        // An overlay rather than a second `VStack` child: `Annotation` centres
        // this view on the rental's coordinate, so anything that adds layout
        // height pushes the circle off the point it is marking. An overlay does
        // not change the frame, so the marker stays 28x28 whether or not the
        // fuel figure is showing. The guide puts the label's top at the circle's
        // bottom, reproducing the 1pt spacing the stack used to provide.
        .overlay(alignment: .bottom) {
            if showsFuelLabel, let fuelText = RentalFormat.fuelLabelText(for: rental) {
                Text(fuelText)
                    .font(.caption.bold())
                    .foregroundStyle(markerColor)
                    // A light halo keeps the figure legible over satellite.
                    .shadow(color: Color(uiColor: .systemBackground), radius: 2)
                    .fixedSize()
                    .alignmentGuide(.bottom) { $0[.top] - 1 }
            }
        }
        // VoiceOver ignores the zoom gate: a visual-density rule must not cost a
        // VoiceOver user information, so the fuel figure is always announced.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var markerColor: Color {
        rental.isOperative ? Color(uiColor: .rentalPurple) : Color(uiColor: .systemGray)
    }

    private var stationAvailabilityText: String? {
        guard case .station(let station) = rental, let available = station.vehiclesAvailableCount else {
            return nil
        }
        return String(available)
    }

    private var glyphName: String {
        guard case .vehicle(let vehicle) = rental, let formFactor = vehicle.vehicleType?.formFactor else {
            return "bicycle"
        }
        if formFactor.isScooter { return "scooter" }
        if formFactor.isBicycle { return "bicycle" }
        switch formFactor {
        case .car: return "car"
        case .moped: return "moped"
        default: return "bicycle"
        }
    }

    private var accessibilityLabel: String {
        [rental.displayLabel, RentalFormat.fuelLabelText(for: rental)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// A group of rentals too close together to draw separately. Mirrors
/// `RentalClusterAnnotationView`: a count badge in rental purple.
struct RentalClusterMapMarker: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .rentalPurple))
                .frame(width: 32, height: 32)
                .shadow(radius: 1, y: 1)

            Text(String(count))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: OBALoc(
                "rental_cluster.title_fmt",
                value: "%d vehicles here",
                comment: "Title of the sheet listing the members of a rental cluster"
            ),
            count
        )))
    }
}
