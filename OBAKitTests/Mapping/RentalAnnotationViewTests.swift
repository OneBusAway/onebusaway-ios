//
//  RentalAnnotationViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import UIKit
import OTPKit
@testable import OBAKit

/// The fuel figure rendered beneath a rental marker. Its visibility is driven by
/// `RentalAnnotation.showsFuelLabel` rather than by the view reading the viewport,
/// because the layer's dequeue path has no access to map state.
@MainActor
@Suite(.serialized)
final class RentalAnnotationViewTests {

    private func view(for rental: VehicleRental, showsFuelLabel: Bool) -> RentalAnnotationView {
        let annotation = RentalAnnotation(rental: rental)
        annotation.showsFuelLabel = showsFuelLabel
        return RentalAnnotationView(annotation: annotation, reuseIdentifier: nil)
    }

    @Test func showsPercentWhenGatedOn() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: true)

        #expect(subject.fuelLabel.text == "62%")
        #expect(subject.fuelLabel.isHidden == false)
    }

    /// The zoom gate hides the label, but the text stays correct so re-showing it
    /// costs nothing.
    @Test func hidesLabelWhenGatedOff() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)
        #expect(subject.fuelLabel.isHidden)
    }

    @Test func hidesLabelWhenThereIsNoFuelData() throws {
        let subject = view(for: try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: nil), showsFuelLabel: true)

        #expect(subject.fuelLabel.text == nil)
        #expect(subject.fuelLabel.isHidden)
    }

    @Test func hidesLabelForStations() throws {
        let subject = view(for: try RentalFixtures.station(), showsFuelLabel: true)
        #expect(subject.fuelLabel.isHidden)
    }

    @Test func labelIsPurpleWhenOperative() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62, operative: true), showsFuelLabel: true)
        #expect(subject.fuelLabel.textColor == .rentalPurple)
    }

    @Test func labelIsGrayWhenNotOperative() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62, operative: false), showsFuelLabel: true)
        #expect(subject.fuelLabel.textColor == .systemGray)
    }

    /// A visual-clutter rule must not cost a VoiceOver user information: the fuel
    /// figure is announced even when the label is hidden by zoom.
    @Test func accessibilityLabelCarriesFuelEvenWhenHidden() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)

        let label = try #require(subject.accessibilityLabel)
        #expect(label.contains("62%"))
    }

    @Test func accessibilityLabelIncludesTheDisplayLabel() throws {
        let rental = try RentalFixtures.vehicle(batteryPercent: 0.62)
        let subject = view(for: rental, showsFuelLabel: true)

        let label = try #require(subject.accessibilityLabel)
        #expect(label.contains(rental.displayLabel))
    }

    /// Assigning `accessibilityLabel` replaces MapKit's title/subtitle default, so
    /// a station's occupancy line has to be carried across explicitly or VoiceOver
    /// users lose it on every browse pass.
    @Test func accessibilityLabelIncludesStationAvailability() throws {
        let annotation = RentalAnnotation(rental: try RentalFixtures.station(vehiclesAvailable: 4))
        annotation.showsFuelLabel = true
        let subtitle = try #require(annotation.subtitle)
        let subject = RentalAnnotationView(annotation: annotation, reuseIdentifier: nil)

        let label = try #require(subject.accessibilityLabel)
        #expect(label.contains(subtitle))
    }

    /// The child label must not be its own element, or VoiceOver announces the
    /// figure twice.
    @Test func childLabelIsNotAnAccessibilityElement() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: true)
        #expect(subject.fuelLabel.isAccessibilityElement == false)
    }

    /// `MKAnnotationView.prepareForReuse()` does nothing by default, so subclass
    /// state that isn't reset by hand leaks into the next annotation.
    @Test func reuseClearsTheLabel() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: true)
        subject.prepareForReuse()

        #expect(subject.fuelLabel.text == nil)
        #expect(subject.fuelLabel.isHidden)
    }

    /// Re-assigning the annotation is how the coordinator pushes a new gate value.
    @Test func reassigningAnnotationRefreshesTheLabel() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)
        #expect(subject.fuelLabel.isHidden)

        let annotation = try #require(subject.annotation as? RentalAnnotation)
        annotation.showsFuelLabel = true
        subject.annotation = annotation

        #expect(subject.fuelLabel.isHidden == false)
    }

    /// A station's glyph is its availability count, not a form-factor symbol.
    @Test func stationWithAvailabilityShowsCountGlyph() throws {
        let subject = view(for: try RentalFixtures.station(vehiclesAvailable: 4), showsFuelLabel: false)
        #expect(subject.glyphText == "4")
    }

    /// When a station's feed omits an availability count, the count glyph falls
    /// back to a form-factor image rather than rendering blank.
    @Test func stationWithoutAvailabilityFallsBackToImageGlyph() throws {
        let subject = view(for: try RentalFixtures.station(vehiclesAvailable: nil), showsFuelLabel: false)
        #expect(subject.glyphText == nil)
        #expect(subject.glyphImage != nil)
    }

    @Test func operativeVehicleTintsPurple() throws {
        let subject = view(for: try RentalFixtures.vehicle(operative: true), showsFuelLabel: false)
        #expect(subject.markerTintColor == .rentalPurple)
    }

    @Test func nonOperativeVehicleTintsGray() throws {
        let subject = view(for: try RentalFixtures.vehicle(operative: false), showsFuelLabel: false)
        #expect(subject.markerTintColor == .systemGray)
    }

    // MARK: - setShowsFuelLabel (the narrow zoom-gate setter)

    /// The coordinator calls this instead of reassigning `.annotation` to avoid a
    /// full `configure()` on every zoom-threshold crossing; it must still show and
    /// hide the label correctly on its own.
    @Test func setShowsFuelLabelTogglesTheLabel() throws {
        let subject = view(for: try RentalFixtures.vehicle(batteryPercent: 0.62), showsFuelLabel: false)
        #expect(subject.fuelLabel.isHidden)

        subject.setShowsFuelLabel(true)
        #expect(subject.fuelLabel.isHidden == false)

        subject.setShowsFuelLabel(false)
        #expect(subject.fuelLabel.isHidden)
    }

    /// Mirrors `configure()`'s own rule: a label with no text stays hidden
    /// regardless of the gate.
    @Test func setShowsFuelLabelKeepsHiddenWhenThereIsNoFuelText() throws {
        let subject = view(for: try RentalFixtures.vehicle(rangeMeters: nil, batteryPercent: nil), showsFuelLabel: false)
        #expect(subject.fuelLabel.text == nil)

        subject.setShowsFuelLabel(true)
        #expect(subject.fuelLabel.isHidden)
    }
}
