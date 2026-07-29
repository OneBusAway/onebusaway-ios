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
}
