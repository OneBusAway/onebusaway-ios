//
//  StopViewModelOnDemandTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// `StopViewModel`'s on-demand card: which services it loads for a stop's
/// `onDemandServiceIds` pointers, when it reloads them, and that a superseded
/// or abandoned load never lands.
@MainActor
@Suite(.serialized)
final class StopViewModelOnDemandTests: OBATestCase {

    nonisolated private static let alexandriaServiceID = "5088_77652"
    private static let fixedRouteStopID = "1_10020"
    private static let fixedRouteArrivals = "arrivals_and_departures_for_stop_1_10020.json"

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// Builds an `Application` over `dataLoader` (or `gate`, when a test holds a
    /// request open), with the surveys and agency-alerts traffic every stop
    /// fetch brings along already stubbed. Arrivals and services are the test's.
    private func makeApplication(dataLoader: MockDataLoader, gate: GatedDataLoader? = nil) -> Application {
        let emptySurveys = Data(#"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.utf8)
        dataLoader.mock(data: emptySurveys) { $0.url?.path.contains("/surveys.json") ?? false }
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        return buildApplication(queue: queue, dataLoader: dataLoader, transport: gate)
    }

    private func arrivals(pointers ids: [String], fixture: String = fixedRouteArrivals) throws -> Data {
        try Fixtures.loadData(file: fixture, stampingOnDemandServiceIDs: ids)
    }

    private func stubArrivals(_ dataLoader: MockDataLoader, _ data: Data, statusCode: Int = 200) {
        dataLoader.mock(data: data, statusCode: statusCode) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }
    }

    /// Stubs arrivals that answer `data` only while `phase` equals `index`, so a
    /// test can change what the next refresh sees. Register every phase before
    /// the first refresh: the loader matches in registration order.
    private func stubArrivals(_ dataLoader: MockDataLoader, phase: SendableBox<Int>, index: Int, _ data: Data, statusCode: Int = 200) {
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            phase.value == index && (request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false)
        }
    }

    private func stubService(_ dataLoader: MockDataLoader) {
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_service_alexandria.json")) { Self.isServiceRequest($0, id: Self.alexandriaServiceID) }
    }

    private func onDemandRequestCount(_ dataLoader: MockDataLoader) -> Int {
        dataLoader.recordedRequestURLs.filter { $0.path.contains("/api/ondemand/service/") }.count
    }

    nonisolated private static func isServiceRequest(_ request: URLRequest, id: String = "") -> Bool {
        request.url?.path.contains("/api/ondemand/service/\(id)") ?? false
    }

    // MARK: - Loading

    @Test func `Stop with a pointer loads its on-demand services once`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubService(dataLoader)
        stubArrivals(dataLoader, try arrivals(pointers: [Self.alexandriaServiceID]))
        let viewModel = StopViewModel(application: makeApplication(dataLoader: dataLoader), stopID: Self.fixedRouteStopID)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(viewModel.onDemandServices.map(\.id) == [Self.alexandriaServiceID])
        #expect(viewModel.onDemandServices[0].areas.first?.hasGeometry == true, "rows fetch simplified geometry for the service page")
        #expect(onDemandRequestCount(dataLoader) == 1)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(onDemandRequestCount(dataLoader) == 1, "same pointer set → no refetch")
    }

    @Test func `Stop without a pointer has no on-demand services and makes no request`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubArrivals(dataLoader, try arrivals(pointers: []))
        let viewModel = StopViewModel(application: makeApplication(dataLoader: dataLoader), stopID: Self.fixedRouteStopID)

        await viewModel.refresh()
        #expect(viewModel.onDemandFetchTask == nil)
        #expect(viewModel.onDemandServices.isEmpty)
        #expect(onDemandRequestCount(dataLoader) == 0)
    }

    /// A flex-only stop has pointers and nothing scheduled. The empty response
    /// walks the arrivals window out in a chain of refreshes, and the load holds
    /// its request open across the whole chain: none of those refreshes may
    /// cancel it and start over.
    @Test func `Flex-only stop with no arrivals loads its services once`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubService(dataLoader)
        stubArrivals(dataLoader, try arrivals(pointers: [Self.alexandriaServiceID], fixture: "arrivals_and_departures_empty.json"))
        let gate = GatedDataLoader(dataLoader) { Self.isServiceRequest($0) }
        let viewModel = StopViewModel(application: makeApplication(dataLoader: dataLoader, gate: gate), stopID: "1_TEST")

        let refreshChain = Task { await viewModel.refresh() }
        await gate.waitForRequest()
        let firstLoad = try #require(viewModel.onDemandFetchTask)
        await refreshChain.value
        #expect(viewModel.stopArrivals?.arrivalsAndDepartures.isEmpty == true)
        #expect(viewModel.isLoadMoreExhausted, "fixture premise: the window was walked out to its cap")
        #expect(viewModel.onDemandFetchTask == firstLoad)
        #expect(!firstLoad.isCancelled)

        gate.releaseRequest()
        await viewModel.onDemandFetchTask?.value
        #expect(viewModel.onDemandServices.map(\.id) == [Self.alexandriaServiceID])
        #expect(onDemandRequestCount(dataLoader) == 1)
    }

    // MARK: - Failures

    @Test func `Failed on-demand load leaves the list empty and retries on the next refresh`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data(), statusCode: 500) { Self.isServiceRequest($0) }
        stubArrivals(dataLoader, try arrivals(pointers: [Self.alexandriaServiceID]))
        let viewModel = StopViewModel(application: makeApplication(dataLoader: dataLoader), stopID: Self.fixedRouteStopID)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(viewModel.onDemandServices.isEmpty)
        #expect(viewModel.operationError == nil, "on-demand failures never fail the arrivals page")
        #expect(onDemandRequestCount(dataLoader) == 1)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(onDemandRequestCount(dataLoader) == 2)
    }

    /// One pointer 404s, the other loads: the missing one is omitted, and because
    /// something loaded the set counts as done — no retry on the next refresh.
    @Test func `A service that fails to load is omitted while the rest show`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubService(dataLoader)
        dataLoader.mock(data: Data(), statusCode: 404) { Self.isServiceRequest($0, id: "5088_missing") }
        stubArrivals(dataLoader, try arrivals(pointers: [Self.alexandriaServiceID, "5088_missing"]))
        let viewModel = StopViewModel(application: makeApplication(dataLoader: dataLoader), stopID: Self.fixedRouteStopID)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(viewModel.onDemandServices.map(\.id) == [Self.alexandriaServiceID])
        #expect(viewModel.operationError == nil)
        #expect(onDemandRequestCount(dataLoader) == 2)

        await viewModel.refresh()
        await viewModel.onDemandFetchTask?.value
        #expect(onDemandRequestCount(dataLoader) == 2, "a partly loaded set is not retried")
    }

    // MARK: - Supersession and cancellation

    /// A refresh that brings a different pointer set cancels the load for the old
    /// one, and the old load's result never lands — even when its request
    /// completes after the newer fetch has applied.
    @Test func `A newer pointer set supersedes an in-flight load`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubService(dataLoader)
        let phase = SendableBox(0)
        stubArrivals(dataLoader, phase: phase, index: 0, try arrivals(pointers: [Self.alexandriaServiceID]))
        stubArrivals(dataLoader, phase: phase, index: 1, try arrivals(pointers: []))
        let gate = GatedDataLoader(dataLoader) { Self.isServiceRequest($0) }
        let viewModel = StopViewModel(application: makeApplication(dataLoader: dataLoader, gate: gate), stopID: Self.fixedRouteStopID)

        await viewModel.refresh()
        let staleTask = try #require(viewModel.onDemandFetchTask)
        await gate.waitForRequest()

        phase.value = 1
        await viewModel.refresh()
        #expect(staleTask.isCancelled)
        #expect(viewModel.onDemandFetchTask == nil)

        gate.releaseRequest()
        await staleTask.value
        #expect(viewModel.onDemandServices.isEmpty, "the superseded load's result never applies")
    }

    @Test func `Releasing the view model cancels its in-flight on-demand load`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubService(dataLoader)
        stubArrivals(dataLoader, try arrivals(pointers: [Self.alexandriaServiceID]))
        let gate = GatedDataLoader(dataLoader) { Self.isServiceRequest($0) }
        var viewModel: StopViewModel? = StopViewModel(application: makeApplication(dataLoader: dataLoader, gate: gate), stopID: Self.fixedRouteStopID)

        await viewModel?.refresh()
        // The survey fetch holds the view model strongly while it runs.
        await viewModel?.surveyRefreshTask?.value
        let task = try #require(viewModel?.onDemandFetchTask)
        await gate.waitForRequest()

        weak var released = viewModel
        viewModel = nil
        #expect(released == nil)
        #expect(task.isCancelled)

        gate.releaseRequest()
        await task.value
    }
}
