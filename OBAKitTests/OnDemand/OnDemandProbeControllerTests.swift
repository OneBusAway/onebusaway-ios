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

    private func makeController() -> OnDemandProbeController {
        let cache = OnDemandGeometryCache { apiService, serviceID in
            try await apiService.getOnDemandService(id: serviceID, geometryDetail: .full).entry.areas
        }
        return OnDemandProbeController(
            apiService: { [weak application] in application?.apiService },
            geometryCache: cache,
            now: { [self] in now }
        )
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
}
