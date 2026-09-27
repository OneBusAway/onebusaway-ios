//
//  MapItemViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Spec 3.7: the one extra line a dropped pin or search result gets.
@MainActor
@Suite(.serialized)
final class MapItemViewModelTests: OBATestCase {

    private var application: Application!
    private let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!

    override init() async throws {
        try await super.init()
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
    }

    private func matches(file: String) throws -> [OnDemandServiceMatch] {
        let services = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: file)).list
        return OnDemandServiceMatch.matches(from: services, now: now)
    }

    private func makeViewModel(probe: OnDemandCoverageProbe?, openDetail: ((OnDemandServiceMatch, OnDemandLocationCheck) -> Void)? = nil) -> MapItemViewModel {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)))
        mapItem.name = "310 Pleasant Ave"
        return MapItemViewModel(
            mapItem: mapItem,
            application: application,
            actions: MapItemActions(openWebsite: { _ in }, showNearbyStops: { _ in }, dismiss: {}, openOnDemandDetail: openDetail),
            removePinHandler: nil,
            planTripHandler: nil,
            coverageProbe: probe
        )
    }

    @Test func `Inside a zone the line names the service`() async throws {
        let inside = try matches(file: "ondemand_services_for_location_point.json")
        let viewModel = makeViewModel(probe: { _ in inside })
        await viewModel.coverageTask?.value
        #expect(viewModel.coverageLine?.text == "Inside DOT Paratransit")
        #expect(viewModel.coverageLine?.isInside == true)
    }

    @Test func `Outside the line names the nearest service within five kilometres`() async throws {
        let near = try matches(file: "ondemand_services_for_location_point_near.json")
        let viewModel = makeViewModel(probe: { _ in near })
        await viewModel.coverageTask?.value
        #expect(viewModel.coverageLine?.text == "Outside Charlevoix County Dial-a-Ride")
        #expect(viewModel.coverageLine?.isInside == false)
    }

    @Test func `No service nearby, an error, or an unsupported deployment yields no line`() async throws {
        let empty = makeViewModel(probe: { _ in [] })
        await empty.coverageTask?.value
        #expect(empty.coverageLine == nil)

        struct Failure: Error {}
        let failed = makeViewModel(probe: { _ in throw Failure() })
        await failed.coverageTask?.value
        #expect(failed.coverageLine == nil)

        let unsupported = makeViewModel(probe: nil)
        #expect(unsupported.coverageTask == nil)
        #expect(unsupported.coverageLine == nil)
    }

    @Test func `A pin in two zones reads inside the first and counts the rest`() throws {
        let inside = try matches(file: "ondemand_services_for_location_point.json")
        let other = try Fixtures.dictionaryToModel(type: OnDemandService.self, dictionary: [
            "id": "5088_other", "agencyId": "5088", "routeId": "5088_other", "name": "Other Zone", "serviceKind": "zone",
            "description": NSNull(), "url": NSNull(), "rules": []
        ])
        let twice = inside + inside.map { match in
            OnDemandServiceMatch(
                service: other,
                matchReason: .areaContainsPoint, distanceToArea: 0, nearestPointOnBoundary: nil, availability: match.availability
            )
        }
        let line = try #require(OnDemandCoverageLine.line(from: twice))
        #expect(line.extraCount == 1)
        #expect(line.text == OnDemandCopy.addressInsideMore(name: line.serviceName, extra: 1))
        #expect(line.serviceName == sortedSoonestUsable(twice)[0].service.name)
    }

    /// Review Focus 5: a match with no area is neither inside nor nearby.
    @Test func `A stop-group-only match yields no coverage line`() throws {
        let ferry = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")).list.first { $0.id == "CC_CC3" }!
        let match = OnDemandServiceMatch(service: ferry, matchReason: .stopWithinRadius, distanceToArea: nil, nearestPointOnBoundary: nil, availability: .unknown)
        #expect(OnDemandCoverageLine.line(from: [match]) == nil)
    }

    @Test func `Tapping the line opens the detail with a point location check`() async throws {
        let inside = try matches(file: "ondemand_services_for_location_point.json")
        var opened: (OnDemandServiceMatch, OnDemandLocationCheck)?
        let viewModel = makeViewModel(probe: { _ in inside }, openDetail: { opened = ($0, $1) })
        await viewModel.coverageTask?.value

        viewModel.openCoverageDetail()

        let check = try #require(opened?.1)
        #expect(opened?.0.id == "5088_77652")
        #expect(check.source == .point(label: "310 Pleasant Ave"))
        #expect(check.isInside)
        #expect(check.coordinate.latitude == 45.3)
    }
}
