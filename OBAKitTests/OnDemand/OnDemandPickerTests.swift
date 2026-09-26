//
//  OnDemandPickerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandPickerTests: OBATestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!
    private let detroit = TimeZone(identifier: "America/Detroit")!
    private let probe = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)

    private func charlevoix() throws -> [OnDemandService] {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")).list
    }

    private func match(_ service: OnDemandService, reason: MatchReason = .areaContainsPoint, distance: Double? = 0) -> OnDemandServiceMatch {
        OnDemandServiceMatch(
            service: service, matchReason: reason, distanceToArea: distance, nearestPointOnBoundary: nil,
            availability: OnDemandAvailability.evaluate(service: service, timeZone: service.timeZone, now: now)
        )
    }

    private var copy: OnDemandCopy { OnDemandCopy(timeZone: detroit, locale: Locale(identifier: "en_US"), now: now) }

    private func model(_ matches: [OnDemandServiceMatch], scope: OnDemandPickerScope, source: ProbeSource = .rider, locality: String? = "Boyne City") throws -> OnDemandPickerModel {
        let services = try charlevoix()
        let request = OnDemandPickerRequest(matches: matches, scope: scope, source: source, coordinate: probe)
        return OnDemandPickerModel(request: request, locality: locality, colors: OnDemandServiceColors.resolvedColors(for: services, brand: ThemeColors.shared.brand), copy: copy)
    }

    @Test func `Rows follow the sort and the inside-only scope drops nearby matches`() throws {
        let services = try charlevoix()
        let matches = [
            match(services.first { $0.id == "CC_CC2_med" }!),
            match(services.first { $0.id == "CC_CC1" }!),
            match(services.first { $0.id == "CC_CC4" }!, reason: .areaNearby, distance: 900)
        ]
        let nearby = try model(matches, scope: .nearby)
        #expect(nearby.rows.map(\.id) == sortedSoonestUsable(matches).map(\.id))
        #expect(nearby.title == OnDemandCopy.pickerTitle(count: 3, nearby: true))

        let inside = try model(matches, scope: .insideOnly)
        #expect(inside.rows.map(\.id) == sortedSoonestUsable(Array(matches.prefix(2))).map(\.id))
        #expect(inside.title == OnDemandCopy.pickerTitle(count: 2, nearby: false))
        #expect(inside.footer == Strings.onDemandPickerFooter)
    }

    @Test func `Subtitle names the source with or without a locality`() {
        #expect(OnDemandPickerModel.subtitle(source: .rider, locality: "Boyne City") == "Boyne City · Your location")
        #expect(OnDemandPickerModel.subtitle(source: .mapCenter, locality: "Boyne City") == "Boyne City · Map center")
        #expect(OnDemandPickerModel.subtitle(source: .point(label: nil), locality: "Boyne City") == "Boyne City · Selected place")
        #expect(OnDemandPickerModel.subtitle(source: .rider, locality: nil) == Strings.onDemandPickerYourLocation)
        #expect(OnDemandPickerModel.subtitle(source: .mapCenter, locality: nil) == Strings.onDemandPickerMapCenter)
        #expect(OnDemandPickerModel.subtitle(source: .point(label: "310 Pleasant Ave"), locality: nil) == Strings.onDemandPickerSelectedPlace)
    }

    @Test func `Row lines are the status and the areas with the booking tag`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let row = try model([match(dialARide)], scope: .insideOnly).rows[0]
        #expect(row.title == "Charlevoix County Dial-a-Ride")
        // `DateFormatter` puts a narrow no-break space (U+202F) before AM/PM.
        #expect(row.statusLine?.replacingOccurrences(of: "\u{202F}", with: " ") == "Open · until 4:40 PM")
        #expect(row.detailLine == "\(OnDemandCopy.zoneCount(1)) · Same-day booking", "Charlevoix's areas are unnamed")
        #expect(row.color == ThemeColors.shared.brand)
    }

    @Test func `Picker route stacks at medium and carries a stable id`() throws {
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let payload = OnDemandPickerPayload(request: OnDemandPickerRequest(matches: [match(dialARide)], scope: .insideOnly, source: .rider, coordinate: probe), locality: nil)
        let route = AppSheetRoute.onDemandPicker(payload)
        #expect(route.id == "onDemandPicker-\(payload.id)")
        #expect(route.prefersStacking)
        #expect(route.detentConfiguration.initialDetent == .medium)
        #expect(route.detentConfiguration.detents == [.medium, .large])
        #expect(route == AppSheetRoute.onDemandPicker(payload))
    }

    @Test func `Factory builds the picker view from the payload`() throws {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let factory = AppSheetViewFactory(
            application: application,
            mapViewModel: MapViewModel(application: application),
            layersModel: MapPanelLayersModel(application: application),
            onPresentTrip: { _ in },
            onPresentVehicleTrip: { _ in },
            presentingController: { nil },
            coordinator: SheetCoordinator(root: .home),
            searchDisplayModel: MapSearchDisplayModel(),
            stopsObserver: MapStopsObserver(application: application)
        )
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let payload = OnDemandPickerPayload(request: OnDemandPickerRequest(matches: [match(dialARide)], scope: .insideOnly, source: .mapCenter, coordinate: probe), locality: "Boyne City")
        let view = factory.onDemandPickerView(payload: payload)
        #expect(view.model.rows.map(\.id) == ["CC_CC1"])
        #expect(view.model.subtitle == "Boyne City · Map center")
    }

    @Test func `Classic picker controller pushes the service page on selection`() throws {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let dialARide = try charlevoix().first { $0.id == "CC_CC1" }!
        let picker = OnDemandPickerViewController(application: application, model: try model([match(dialARide)], scope: .insideOnly), onHighlight: { _ in })
        #expect(picker.viewControllers.count == 1)

        picker.select(match(dialARide), check: OnDemandLocationCheck(source: .rider, isInside: true, locality: "Boyne City", coordinate: probe))
        #expect(picker.viewControllers.count == 2)
        #expect(picker.viewControllers.last is OnDemandServiceViewController)
    }
}
