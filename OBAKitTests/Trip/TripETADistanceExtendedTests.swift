//
//  TripETADistanceExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `TripETADistance` boundary conditions, non-finite values,
/// pluralization boundaries, and ArrivalDeparture-backed factory paths.
@Suite(.serialized)
struct TripETADistanceExtendedTests {

    private let imperialFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.units = .imperial
        return formatter
    }()

    private let metricFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.units = .metric
        return formatter
    }()

    private func make(
        distance: Double,
        stops: Int,
        predicted: Bool = true,
        formatter: MKDistanceFormatter? = nil,
        locale: Locale = Locale(identifier: "en_US")
    ) -> TripETADistance? {
        TripETADistance.make(
            distanceMeters: distance,
            stopsAway: stops,
            isPredicted: predicted,
            formatter: formatter ?? imperialFormatter,
            locale: locale
        )
    }

    private var expectedArrivingText: String {
        OBALoc(
            "trip_page.card.arriving_at_stop",
            value: "Arriving at your stop",
            comment: ""
        )
    }

    // MARK: - Zero and Boundary Thresholds

    @Test func `Zero distance with positive stops indicates arriving at your stop`() throws {
        let line = try #require(make(distance: 0.0, stops: 4))
        #expect(line.text == expectedArrivingText)
        #expect(line.accessibilityText == expectedArrivingText)
    }

    @Test func `Positive distance with zero stops indicates arriving at your stop`() throws {
        let line = try #require(make(distance: 450.0, stops: 0))
        #expect(line.text == expectedArrivingText)
        #expect(line.accessibilityText == expectedArrivingText)
    }

    @Test func `Zero distance and zero stops indicates arriving at your stop`() throws {
        let line = try #require(make(distance: 0.0, stops: 0))
        #expect(line.text == expectedArrivingText)
        #expect(line.accessibilityText == expectedArrivingText)
    }

    // MARK: - Negative and Non-finite Values

    @Test func `Negative distance or negative stops yields nil regardless of prediction`() {
        #expect(make(distance: -1.0, stops: 1, predicted: true) == nil)
        #expect(make(distance: 100.0, stops: -1, predicted: true) == nil)
        #expect(make(distance: -500.0, stops: -3, predicted: true) == nil)
        #expect(make(distance: -100.0, stops: 0, predicted: true) == nil)
    }

    @Test func `Non-finite distances yield nil`() {
        #expect(make(distance: Double.infinity, stops: 2) == nil)
        #expect(make(distance: -Double.infinity, stops: 2) == nil)
        #expect(make(distance: Double.nan, stops: 2) == nil)
    }

    @Test func `Unpredicted trips always yield nil`() {
        #expect(make(distance: 1000.0, stops: 5, predicted: false) == nil)
        #expect(make(distance: 0.0, stops: 0, predicted: false) == nil)
    }

    // MARK: - Pluralization and Stop Counts

    @Test func `Two or more stops away formats with expected stop count and distance string`() throws {
        let locale = Locale(identifier: "en_US")
        let distance = defaultFormatter.string(fromDistance: 1609.34)
        let line = try #require(make(distance: 1609.34, stops: 2, locale: locale))

        let expectedFmt = OBALoc("trip_page.card.distance_stops_fmt", value: "%1$@ away · %2$d stops", comment: "")
        let expectedA11y = OBALoc("trip_page.card.distance_stops_a11y_fmt", value: "%1$@ away, %2$d stops away", comment: "")

        #expect(line.text == String(format: expectedFmt, locale: locale, distance, 2))
        #expect(line.accessibilityText == String(format: expectedA11y, locale: locale, distance, 2))
    }

    @Test func `Large stop counts format cleanly with expected text`() throws {
        let locale = Locale(identifier: "en_US")
        let distance = defaultFormatter.string(fromDistance: 8000.0)
        let line = try #require(make(distance: 8000.0, stops: 24, locale: locale))

        let expectedFmt = OBALoc("trip_page.card.distance_stops_fmt", value: "%1$@ away · %2$d stops", comment: "")
        let expectedA11y = OBALoc("trip_page.card.distance_stops_a11y_fmt", value: "%1$@ away, %2$d stops away", comment: "")

        #expect(line.text == String(format: expectedFmt, locale: locale, distance, 24))
        #expect(line.accessibilityText == String(format: expectedA11y, locale: locale, distance, 24))
    }

    // MARK: - Formatter and Metric Locales

    @Test func `Metric formatter renders kilometer units`() throws {
        let line = try #require(make(distance: 3000.0, stops: 5, formatter: metricFormatter, locale: Locale(identifier: "fr_FR")))
        #expect(line.text.contains("km"))
        #expect(!line.text.contains("mi"))
    }

    // MARK: - Equatable Conformance

    @Test func `TripETADistance equality and inequality`() {
        let a = TripETADistance(text: "1 mi away · 2 stops", accessibilityText: "1 mi away, 2 stops away")
        let b = TripETADistance(text: "1 mi away · 2 stops", accessibilityText: "1 mi away, 2 stops away")
        let c = TripETADistance(text: expectedArrivingText, accessibilityText: expectedArrivingText)

        #expect(a == b)
        #expect(a != c)
    }
}
