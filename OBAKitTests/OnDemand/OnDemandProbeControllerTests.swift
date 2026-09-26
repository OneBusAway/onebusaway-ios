//
//  OnDemandProbeControllerTests.swift
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

@MainActor
@Suite(.serialized)
final class OnDemandProbeControllerTests: OBATestCase {

    private var application: Application!
    private var dataLoader: MockDataLoader!
    private let clock = TestClock()
    /// Tuesday 2026-03-10 15:09 EDT: CC1 is running and bookable for one more minute.
    private let baseNow = ISO8601DateFormatter().date(from: "2026-03-10T19:09:00Z")!

    /// Inside Alexandria's zone (the `_point.json` fixture's probe point).
    private let alexandriaPoint = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.05)
    /// Near Charlevoix's zone (the `_point_near.json` fixture).
    private let charlevoixPoint = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.tampaRegion.OBABaseURL)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
    }

    private var now: Date {
        baseNow.addingTimeInterval(Double(clock.now.offset.components.seconds))
    }

    private func makeController(authorized: Bool = false, configuration: OnDemandProbeController.Configuration = .init()) -> OnDemandProbeController {
        mockGeometryFallback()
        let cache = OnDemandGeometryCache { apiService, serviceID in
            try await apiService.getOnDemandService(id: serviceID, geometryDetail: .full).entry.areas
        }
        let clock = self.clock
        return OnDemandProbeController(
            apiService: { [weak application] in application?.apiService },
            geometryCache: cache,
            now: { [self] in now },
            configuration: configuration,
            isLocationAuthorized: { authorized },
            sleep: { seconds in try await clock.sleep(for: .seconds(seconds), tolerance: nil) }
        )
    }

    /// A settle loads full geometry for every match (spec 2.7), and the mock
    /// loader traps on an unmatched request. First match wins, so this 500
    /// only answers services the test did not mock itself.
    private func mockGeometryFallback() {
        dataLoader.mock(data: Data(), statusCode: 500, matcher: Self.isGeometry)
    }

    private func mockProbe(file: String) {
        dataLoader.mock(data: Fixtures.loadData(file: file)) { request in
            request.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }
    }

    private func mockProbe(statusCode: Int) {
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            request.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }
    }

    private var probeRequests: [URL] {
        dataLoader.recordedRequestURLs.filter { $0.path.contains("/api/ondemand/services-for-location") }
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private nonisolated static func isProbe(_ request: URLRequest) -> Bool {
        request.url?.path.contains("/api/ondemand/services-for-location") ?? false
    }

    private nonisolated static func isGeometry(_ request: URLRequest) -> Bool {
        request.url?.path.contains("/api/ondemand/service/") ?? false
    }

    // MARK: - Point probe

    @Test func `Probe requests point mode with the dock radius and no geometry`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()

        let matches = try await controller.probe(at: alexandriaPoint)

        #expect(matches.map(\.id) == ["5088_77652"])
        #expect(matches[0].isInside)
        let request = try #require(probeRequests.last)
        #expect(query(request, "radius").flatMap(Double.init) == 5000)
        #expect(query(request, "geometryDetail") == "none")
        #expect(query(request, "latSpan") == nil)
    }

    @Test func `Probes within the rounding key share one response`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()

        _ = try await controller.probe(at: alexandriaPoint)
        _ = try await controller.probe(at: CLLocationCoordinate2D(latitude: 38.8001, longitude: -77.0501))

        #expect(probeRequests.count == 1)
    }

    @Test func `A cached probe expires after ten minutes`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()

        _ = try await controller.probe(at: alexandriaPoint)
        clock.advance(by: .seconds(599))
        _ = try await controller.probe(at: alexandriaPoint)
        #expect(probeRequests.count == 1)

        clock.advance(by: .seconds(2))
        _ = try await controller.probe(at: alexandriaPoint)
        #expect(probeRequests.count == 2)
    }

    @Test func `A stale entry is reused when allowed`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()

        _ = try await controller.probe(at: alexandriaPoint)
        clock.advance(by: .seconds(700))
        _ = try await controller.probe(at: alexandriaPoint, allowStale: true)
        #expect(probeRequests.count == 1)
    }

    @Test func `Availability is recomputed at the probe time`() async throws {
        mockProbe(file: "ondemand_services_for_location_point_near.json")
        let controller = makeController()

        let before = try await controller.probe(at: charlevoixPoint)
        #expect(before[0].availability.bookableNow)

        clock.advance(by: .seconds(120)) // past the 15:10 cutoff
        let after = try await controller.probe(at: charlevoixPoint)
        #expect(!after[0].availability.bookableNow)
        #expect(probeRequests.count == 1, "recomputed from the cached response")
    }

    // MARK: - Exact probe

    @Test func `probeExact never returns the rider cache's entry for a point 20 metres away`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        _ = try await controller.probe(at: alexandriaPoint)

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Fixtures.loadData(file: "ondemand_services_for_location_point_near.json"), matcher: Self.isProbe)
        }
        let twentyMetresAway = CLLocationCoordinate2D(latitude: 38.80018, longitude: -77.05)
        let exact = try await controller.probeExact(at: twentyMetresAway)

        #expect(exact.map(\.id) == ["CC_CC1"], "the exact probe went to the network")
        #expect(probeRequests.count == 2)
    }

    /// A rider probe at 38.8001 rounds to the key 38.8, which an exact probe at
    /// 38.8 also produces; the exact probe must still make its own request.
    @Test func `probeExact never joins a rider probe in flight at an equal key`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let gate = GatedDataLoader(dataLoader, gating: { request in
            Self.isProbe(request) && (request.url?.query?.contains("lat=38.8001") ?? false)
        }, holdsAfterResponse: true)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader, transport: gate)
        let controller = makeController()

        let riderProbe = Task { try await controller.probe(at: CLLocationCoordinate2D(latitude: 38.8001, longitude: -77.0501)) }
        await gate.waitForRequest()

        let exactProbe = Task { try await controller.probeExact(at: alexandriaPoint) }
        await poll(until: { self.probeRequests.count == 2 }, "the exact probe should make its own request while the rider probe is held")

        gate.releaseRequest()
        _ = try await riderProbe.value
        #expect(try await exactProbe.value.map(\.id) == ["5088_77652"])
    }

    @Test func `probeExact keeps its own cache keyed to five decimals`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()

        _ = try await controller.probeExact(at: alexandriaPoint)
        _ = try await controller.probeExact(at: CLLocationCoordinate2D(latitude: 38.800004, longitude: -77.050004))
        #expect(probeRequests.count == 1)

        _ = try await controller.probeExact(at: CLLocationCoordinate2D(latitude: 38.80002, longitude: -77.05))
        #expect(probeRequests.count == 2)
    }

    // MARK: - Errors and deployment

    @Test func `A 404 marks the deployment unsupported and stops probing`() async throws {
        mockProbe(statusCode: 404)
        let controller = makeController()

        await #expect(throws: APIError.self) { _ = try await controller.probe(at: alexandriaPoint) }
        #expect(controller.isUnsupported)
        #expect(application.apiService!.onDemandSupport.isKnownUnsupported(baseURL: application.apiService!.baseURL))

        await #expect(throws: OnDemandProbeController.ProbeError.self) { _ = try await controller.probeExact(at: alexandriaPoint) }
        #expect(probeRequests.count == 1)
    }

    @Test func `A server error is rethrown and not cached`() async throws {
        mockProbe(statusCode: 500)
        let controller = makeController()

        await #expect(throws: (any Error).self) { _ = try await controller.probe(at: alexandriaPoint) }
        #expect(!controller.isUnsupported)

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Fixtures.loadData(file: "ondemand_services_for_location_point.json"), matcher: Self.isProbe)
        }
        let matches = try await controller.probe(at: alexandriaPoint)
        #expect(matches.count == 1)
    }

    @Test func `A deployment change cancels an in-flight probe and discards its result`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let gate = GatedDataLoader(dataLoader, gating: Self.isProbe, holdsAfterResponse: true)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader, transport: gate)
        let controller = makeController()
        let originalDeployment = controller.deployment

        let probe = Task { try await controller.probe(at: alexandriaPoint) }
        await gate.waitForRequest()

        application.regionsService.currentRegion = Fixtures.tampaRegion
        controller.deploymentDidChange()
        gate.releaseRequest()

        await #expect(throws: (any Error).self) { _ = try await probe.value }
        #expect(controller.currentDeployment != originalDeployment)
        #expect(controller.currentDeployment == application.apiService?.baseURL.absoluteString)
    }

    /// Keys carry the deployment, so only a switch away and back shows the
    /// old entry was dropped rather than merely unreachable.
    @Test func `A deployment change drops the probe caches`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()

        _ = try await controller.probe(at: alexandriaPoint)
        _ = try await controller.probeExact(at: alexandriaPoint)

        application.regionsService.currentRegion = Fixtures.tampaRegion
        controller.deploymentDidChange()
        application.regionsService.currentRegion = Fixtures.pugetSoundRegion
        controller.deploymentDidChange()

        _ = try await controller.probe(at: alexandriaPoint)
        _ = try await controller.probeExact(at: alexandriaPoint)
        #expect(probeRequests.count == 4)
    }

    @Test func `A deployment change discards a joined probe's result for every awaiter`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let gate = GatedDataLoader(dataLoader, gating: Self.isProbe, holdsAfterResponse: true)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader, transport: gate)
        let controller = makeController()

        let owner = Task { try await controller.probe(at: alexandriaPoint) }
        await gate.waitForRequest()
        let joiner = Task { try await controller.probe(at: alexandriaPoint) }
        for _ in 0..<10 { await Task.yield() }

        application.regionsService.currentRegion = Fixtures.tampaRegion
        controller.deploymentDidChange()
        gate.releaseRequest()

        await #expect(throws: (any Error).self) { _ = try await owner.value }
        await #expect(throws: (any Error).self) { _ = try await joiner.value }
        #expect(probeRequests.count == 1, "the joiner shared the held request")

        _ = try await controller.probe(at: alexandriaPoint)
        #expect(probeRequests.count == 2, "the discarded result was not cached")
    }

    @Test func `A deployment change discards an in-flight geometry fetch`() async throws {
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_service_alexandria.json"), matcher: Self.isGeometry)
        let gate = GatedDataLoader(dataLoader, gating: Self.isGeometry, holdsAfterResponse: true)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader, transport: gate)
        let controller = makeController()

        let fetch = Task { try await controller.fullAreas(for: "5088_77652") }
        await gate.waitForRequest()

        application.regionsService.currentRegion = Fixtures.tampaRegion
        controller.deploymentDidChange()
        gate.releaseRequest()

        await #expect(throws: (any Error).self) { _ = try await fetch.value }
    }

    @Test func `Cache keys are rounded to the requested decimals`() {
        let key = OnDemandProbeController.cacheKey(for: CLLocationCoordinate2D(latitude: 45.30049, longitude: -85.20051), decimals: 3)
        #expect(key.latitude == 45.3)
        #expect(key.longitude == -85.201)
        let exact = OnDemandProbeController.cacheKey(for: CLLocationCoordinate2D(latitude: 45.300004, longitude: -85.2), decimals: 5)
        #expect(exact.latitude == 45.3)
    }

    // MARK: - Geometry cache

    @Test func `Full geometry is fetched once per service`() async throws {
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_service_alexandria.json")) { request in
            request.url?.path.contains("/api/ondemand/service/5088_77652.json") ?? false
        }
        let controller = makeController()

        let first = try await controller.fullAreas(for: "5088_77652")
        let second = try await controller.fullAreas(for: "5088_77652")

        #expect(first.count == 1)
        #expect(first[0].hasGeometry)
        #expect(second.count == 1)
        let geometryRequests = dataLoader.recordedRequestURLs.filter { $0.path.contains("/api/ondemand/service/") }
        #expect(geometryRequests.count == 1)
        #expect(query(geometryRequests[0], "geometryDetail") == "full")
    }

    // MARK: - Dock state (spec 2.4)

    private func settle(_ controller: OnDemandProbeController, at point: CLLocationCoordinate2D, level: OnDemandZoomLevel) async {
        controller.mapDidSettle(center: point, zoomLevel: level)
        await controller.refreshTask?.value
    }

    private func ids(of state: OnDemandDockState) -> [String]? {
        switch state {
        case .card(let matches), .bar(let matches): return matches.map(\.id)
        default: return nil
        }
    }

    @Test func `A region-level settle inside a zone shows the card`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .region)

        guard case .card(let matches) = controller.dockState else {
            Issue.record("expected card, got \(controller.dockState)")
            return
        }
        #expect(matches.map(\.id) == ["5088_77652"])
        #expect(controller.probeSource == .mapCenter)
        #expect(controller.locationCheck?.isInside == true)
        #expect(controller.locationCheck?.source == .mapCenter)
    }

    @Test func `A pin's location check covers only a matched service`() async {
        mockProbe(file: "ondemand_services_for_location_point_near.json")
        let controller = makeController()
        await settle(controller, at: charlevoixPoint, level: .street)

        let check = controller.locationCheck(forServiceID: "CC_CC1")
        #expect(check?.source == .mapCenter)
        #expect(check?.isInside == false)
        #expect(check?.coordinate.latitude == charlevoixPoint.latitude)
        #expect(controller.locationCheck(forServiceID: "not-a-match") == nil)
    }

    @Test func `A street-level settle inside a zone shows the bar`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        #expect(ids(of: controller.dockState) == ["5088_77652"])
        if case .bar = controller.dockState { } else { Issue.record("expected bar") }
    }

    @Test func `A street-level settle near a zone shows the outside bar with the server edge`() async {
        mockProbe(file: "ondemand_services_for_location_point_near.json")
        let controller = makeController()
        await settle(controller, at: charlevoixPoint, level: .street)

        guard case .bar(let matches) = controller.dockState else {
            Issue.record("expected bar, got \(controller.dockState)")
            return
        }
        #expect(matches.map(\.id) == ["CC_CC1"])
        #expect(!matches[0].isInside)
        #expect(controller.edgesByServiceID["CC_CC1"]?.distanceMeters == 850)
        #expect(controller.edgesByServiceID["CC_CC1"]?.riderDirection == .south, "the boundary point is 850 m due north of the probe")
        #expect(controller.locationCheck?.isInside == false)
    }

    @Test func `Region level near a zone and the hidden level show nothing`() async {
        mockProbe(file: "ondemand_services_for_location_point_near.json")
        let controller = makeController()
        await settle(controller, at: charlevoixPoint, level: .region)
        #expect(controller.dockState == .hidden)

        mockProbe(file: "ondemand_services_for_location_point.json")
        await settle(controller, at: alexandriaPoint, level: .hidden)
        #expect(controller.dockState == .hidden)
    }

    /// Review Focus 5: a pure stop group has no area and no distance.
    @Test func `A stop-group-only match never shows the dock`() async throws {
        let near = try #require(String(data: Fixtures.loadData(file: "ondemand_services_for_location_point_near.json"), encoding: .utf8))
        let stopGroup = near
            .replacingOccurrences(of: "\"matchReason\":\"areaNearby\"", with: "\"matchReason\":\"stopWithinRadius\"")
            .replacingOccurrences(of: "\"distanceToArea\":850,\"nearestPointOnBoundary\":[-85.2,45.30765]", with: "\"distanceToArea\":null,\"nearestPointOnBoundary\":null")
        dataLoader.mock(data: Data(stopGroup.utf8), matcher: Self.isProbe)
        let controller = makeController()
        await settle(controller, at: charlevoixPoint, level: .street)
        #expect(controller.matches.count == 1)
        #expect(controller.dockState == .hidden)
    }

    // MARK: - Triggers (spec 2.1)

    @Test func `A settle under 100 metres does not re-probe`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .region)
        await settle(controller, at: CLLocationCoordinate2D(latitude: 38.8004, longitude: -77.05), level: .region) // ~45 m
        #expect(probeRequests.count == 1)

        await settle(controller, at: CLLocationCoordinate2D(latitude: 38.8014, longitude: -77.05), level: .region) // ~155 m
        #expect(probeRequests.count == 2)
    }

    @Test func `A location update 150 metres away re-probes and a poor fix does not`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController(authorized: true)

        controller.locationDidUpdate(CLLocation(latitude: alexandriaPoint.latitude, longitude: alexandriaPoint.longitude))
        await controller.refreshTask?.value
        #expect(controller.probeSource == .rider, "the first fix switches the source to the rider")
        #expect(probeRequests.count == 1)

        controller.locationDidUpdate(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 38.80135, longitude: -77.05), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: now))
        await controller.refreshTask?.value
        #expect(probeRequests.count == 2)

        controller.locationDidUpdate(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 38.804, longitude: -77.05), altitude: 0, horizontalAccuracy: 200, verticalAccuracy: 10, timestamp: now))
        await controller.refreshTask?.value
        #expect(probeRequests.count == 2, "a fix worse than 100 m is ignored")
    }

    @Test func `Without location authorization the map centre stays the source`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController(authorized: false)
        controller.locationDidUpdate(CLLocation(latitude: 45.3, longitude: -85.2))
        await controller.refreshTask?.value
        #expect(probeRequests.isEmpty)

        await settle(controller, at: alexandriaPoint, level: .region)
        #expect(controller.probeSource == .mapCenter)
    }

    @Test func `A failed probe near the last one keeps the state and far away hides the dock`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        // A one-second cache lets the foreground probe hit the network without
        // advancing the clock far enough to wake the boundary refresh, which
        // would answer from the stale cache and skip the failure path.
        let controller = makeController(configuration: .init(cacheLifetime: 1))
        await settle(controller, at: alexandriaPoint, level: .region)
        #expect(ids(of: controller.dockState) == ["5088_77652"])
        let nextChange = try #require(controller.matches[0].availability.nextChangeInstant)
        #expect(nextChange.timeIntervalSince(now) > 2, "the advance below must stay short of the boundary refresh")
        await poll(until: { self.clock.sleeperCount >= 1 }, "the boundary task should be sleeping until the next change")

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Data(), statusCode: 500, matcher: Self.isProbe)
            staging.mock(data: Data(), statusCode: 500, matcher: Self.isGeometry)
        }
        clock.advance(by: .seconds(2))
        controller.applicationWillEnterForeground()
        await controller.refreshTask?.value
        #expect(probeRequests.count == 2, "the foreground probe reached the network and got the 500")
        #expect(ids(of: controller.dockState) == ["5088_77652"], "a failed re-probe at the last good probe point keeps the state")

        await settle(controller, at: CLLocationCoordinate2D(latitude: 38.82, longitude: -77.05), level: .region) // ~2 km
        #expect(probeRequests.count == 3)
        #expect(controller.dockState == .hidden)
    }

    @Test func `The boundary refresh recomputes from the cache without a network call`() async {
        mockProbe(file: "ondemand_services_for_location_point_near.json")
        let controller = makeController()
        await settle(controller, at: charlevoixPoint, level: .street)
        #expect(controller.matches[0].availability.bookableNow)
        #expect(controller.boundaryTask != nil)

        // Advance only once the boundary task has parked: a sleeper that
        // registers after the advance gets a deadline 62 s later and never wakes.
        await poll(until: { self.clock.sleeperCount >= 1 }, "the boundary task should be sleeping until the cutoff")
        clock.advance(by: .seconds(62)) // 15:10 cutoff + 1 s
        await controller.boundaryTask?.value
        await controller.refreshTask?.value

        #expect(!controller.matches[0].availability.bookableNow)
        if case .opensAt = controller.matches[0].availability.status { } else { Issue.record("expected opensAt, got \(controller.matches[0].availability.status)") }
        #expect(probeRequests.count == 1)
    }

    @Test func `A 404 hides the dock`() async {
        mockProbe(statusCode: 404)
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .region)
        #expect(controller.dockState == .hidden)
        #expect(controller.isUnsupported)
    }

    @Test func `A deployment change hides the dock and clears the highlight`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        controller.highlightedServiceID = "5088_77652"

        application.regionsService.currentRegion = Fixtures.tampaRegion
        controller.deploymentDidChange()

        #expect(controller.dockState == .hidden)
        #expect(controller.highlightedServiceID == nil)
        #expect(controller.matches.isEmpty)
    }

    @Test func `The highlight clears when the dock leaves the bar state`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        controller.highlightedServiceID = "5088_77652"

        await settle(controller, at: alexandriaPoint, level: .region)
        #expect(controller.highlightedServiceID == nil)
        if case .card = controller.dockState { } else { Issue.record("expected card") }
    }

    @Test func `Leaving the bar for hidden clears the highlight`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        controller.highlightedServiceID = "5088_77652"

        controller.setSurfaceFocus(true)
        #expect(controller.dockState == .hidden)
        #expect(controller.highlightedServiceID == nil)
    }

    /// Spec 2.3: a highlight set by the picker or held for the detail page
    /// while the dock is suppressed survives refreshes that keep it hidden.
    @Test func `A highlight set while the dock is hidden survives a trigger`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        controller.setSurfaceFocus(true)
        controller.highlightedServiceID = "5088_77652"

        controller.applicationWillEnterForeground()
        await controller.refreshTask?.value
        await settle(controller, at: CLLocationCoordinate2D(latitude: 38.8004, longitude: -77.05), level: .street)

        #expect(controller.dockState == .hidden)
        #expect(controller.highlightedServiceID == "5088_77652")
    }

    @Test func `Focus, coverage and the layer toggle hide the dock without dropping the matches`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .region)

        controller.setSurfaceFocus(true)
        #expect(controller.dockState == .hidden)
        controller.setSurfaceFocus(false)
        if case .card = controller.dockState { } else { Issue.record("expected card") }

        controller.setMapMostlyCovered(true)
        #expect(controller.dockState == .hidden)
        controller.setMapMostlyCovered(false)

        controller.setLayerEnabled(false)
        #expect(controller.dockState == .hidden)
        #expect(controller.matches.count == 1, "the address check still needs the probe")
        controller.setLayerEnabled(true)
        if case .card = controller.dockState { } else { Issue.record("expected card") }
    }

    // MARK: - Geometry for matches (spec 2.7)

    @Test func `Full geometry loads lazily for matched services and yields an inside edge`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_service_alexandria.json")) { request in
            request.url?.path.contains("/api/ondemand/service/5088_77652.json") ?? false
        }
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        await controller.geometryTask?.value

        #expect(controller.fullAreasByServiceID["5088_77652"]?.first?.hasGeometry == true)
        let edge = controller.edgesByServiceID["5088_77652"]
        #expect((edge?.distanceMeters ?? 0) > 0, "inside: the client edge is the only one")
    }

    @Test func `A failed geometry fetch is remembered for the placeholder thumbnail`() async {
        mockProbe(file: "ondemand_services_for_location_point.json")
        dataLoader.mock(data: Data(), statusCode: 500) { request in
            request.url?.path.contains("/api/ondemand/service/5088_77652.json") ?? false
        }
        let controller = makeController()
        await settle(controller, at: alexandriaPoint, level: .street)
        await controller.geometryTask?.value

        #expect(controller.failedGeometryServiceIDs.contains("5088_77652"))
        #expect(controller.edgesByServiceID["5088_77652"] == nil)
    }

    // MARK: - Planner fallback (spec 3.8)

    @Test func `The planner state survives the semi-modal hide rule and clears on demand`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        controller.setSurfaceFocus(true)

        let result = try #require(await controller.plannerResult(origin: alexandriaPoint, destination: alexandriaPoint))
        controller.showPlanner(result)
        #expect(controller.dockState == .planner(result))
        #expect(result.qualifying.map(\.id) == ["5088_77652"])

        controller.clearPlanner()
        #expect(controller.dockState == .hidden)
    }

    @Test func `The planner probes both ends through the exact cache`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        _ = try await controller.probe(at: alexandriaPoint)

        _ = await controller.plannerResult(origin: alexandriaPoint, destination: CLLocationCoordinate2D(latitude: 38.81, longitude: -77.05))
        #expect(probeRequests.count == 3, "one rider probe plus one exact probe per end")
    }

    /// Decision 5: a routine reprobe, successful or failed, never replaces the
    /// planner state; only `clearPlanner()` does.
    @Test func `A reprobe keeps the planner state until it is cleared`() async throws {
        mockProbe(file: "ondemand_services_for_location_point.json")
        let controller = makeController()
        let result = try #require(await controller.plannerResult(origin: alexandriaPoint, destination: alexandriaPoint))
        controller.showPlanner(result)

        await settle(controller, at: alexandriaPoint, level: .street)
        #expect(controller.dockState == .planner(result), "a successful reprobe keeps the planner")

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Data(), statusCode: 500, matcher: Self.isProbe)
            staging.mock(data: Data(), statusCode: 500, matcher: Self.isGeometry)
        }
        await settle(controller, at: CLLocationCoordinate2D(latitude: 38.82, longitude: -77.05), level: .street) // ~2 km
        #expect(controller.dockState == .planner(result), "a failed reprobe far away keeps the planner")

        controller.clearPlanner()
        #expect(controller.dockState == .hidden)
    }
}
