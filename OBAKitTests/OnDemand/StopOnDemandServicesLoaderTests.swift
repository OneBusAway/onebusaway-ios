//
//  StopOnDemandServicesLoaderTests.swift
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

/// `StopOnDemandServicesLoader` feeds the stop page's on-demand card. Every
/// test awaits `task`, so none of them waits on a clock.
@MainActor
@Suite(.serialized)
final class StopOnDemandServicesLoaderTests: OBATestCase {

    private var dataLoader: MockDataLoader!
    private var apiService: RESTAPIService!
    private var reports: [[String]] = []
    private var loader: StopOnDemandServicesLoader!

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        apiService = buildRESTService(dataLoader: dataLoader)
        loader = StopOnDemandServicesLoader { [unowned self] services in
            reports.append(services.map(\.name))
        }
    }

    // MARK: - Helpers

    /// `file`'s JSON with `edit` applied to its `data.entry`.
    private func editingEntry(of file: String, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: file)) as? [String: Any])
        var payload = try #require(json["data"] as? [String: Any])
        var entry = try #require(payload["entry"] as? [String: Any])
        edit(&entry)
        payload["entry"] = entry
        json["data"] = payload
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// A stop whose `onDemandServiceIDs` are `ids`.
    private func stop(ids: [String]) throws -> Stop {
        let data = try editingEntry(of: "stop_with_ondemand_pointer.json") { $0["onDemandServiceIds"] = ids }
        let stop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: data).entry
        try #require(stop.onDemandServiceIDs == ids)
        return stop
    }

    /// Serves service `id`, named `name`, from the Alexandria fixture.
    private func mockService(id: String, name: String) throws {
        let data = try editingEntry(of: "ondemand_service_alexandria.json") {
            $0["id"] = id
            $0["name"] = name
        }
        dataLoader.mock(data: data) { $0.url?.path.hasSuffix("/api/ondemand/service/\(id).json") ?? false }
    }

    private func mockFailure(id: String) {
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path.hasSuffix("/api/ondemand/service/\(id).json") ?? false }
    }

    private var serviceRequests: Int {
        dataLoader.recordedRequestURLs.filter { $0.path.contains("/api/ondemand/service/") }.count
    }

    private func refresh(_ ids: [String]) async throws {
        loader.refresh(for: try stop(ids: ids), apiService: apiService)
        await loader.task?.value
    }

    // MARK: - Tests

    @Test func `A stop without on-demand services reports an empty list without a request`() async throws {
        try await refresh([])

        #expect(reports == [[]])
        #expect(loader.task == nil)
        #expect(serviceRequests == 0)
    }

    @Test func `Without an API service it reports an empty list without a request`() async throws {
        loader.refresh(for: try stop(ids: ["CC_CC3"]), apiService: nil)

        #expect(reports == [[]])
        #expect(loader.task == nil)
        #expect(serviceRequests == 0)
    }

    /// The server's order is the order of the stop's pointers; the card lists
    /// them by name.
    @Test func `Services are reported sorted by name`() async throws {
        try mockService(id: "z", name: "Zeta Dial-a-Ride")
        try mockService(id: "a", name: "Alpha Paratransit")

        try await refresh(["z", "a"])

        #expect(reports == [["Alpha Paratransit", "Zeta Dial-a-Ride"]])
        #expect(serviceRequests == 2)
    }

    /// A service that fails is left out rather than failing the card.
    @Test func `A service that fails to load is left out`() async throws {
        try mockService(id: "a", name: "Alpha Paratransit")
        mockFailure(id: "b")

        try await refresh(["a", "b"])

        #expect(reports == [["Alpha Paratransit"]])
    }

    /// The stop page refreshes on every departures reload, so an unchanged set
    /// must not refetch.
    @Test func `Refreshing with the same services loads them once`() async throws {
        try mockService(id: "a", name: "Alpha Paratransit")

        try await refresh(["a"])
        try await refresh(["a"])

        #expect(reports == [["Alpha Paratransit"]])
        #expect(serviceRequests == 1)
    }

    /// Auto-extension fires several refreshes while the first load is running.
    @Test func `A refresh during a load of the same services doesn't restart it`() async throws {
        try mockService(id: "a", name: "Alpha Paratransit")
        loader.refresh(for: try stop(ids: ["a"]), apiService: apiService)
        let first = try #require(loader.task)

        loader.refresh(for: try stop(ids: ["a"]), apiService: apiService)
        #expect(loader.task == first)
        await first.value

        #expect(reports == [["Alpha Paratransit"]])
        #expect(serviceRequests == 1)
    }

    /// A load where every service failed forgets the set, so the next refresh
    /// tries again instead of leaving the card empty for the page's lifetime.
    @Test func `A load that finds nothing lets the next refresh retry`() async throws {
        mockFailure(id: "a")

        try await refresh(["a"])
        #expect(reports == [[]])
        #expect(serviceRequests == 1)

        try await refresh(["a"])
        #expect(reports == [[], []])
        #expect(serviceRequests == 2)
    }

    /// The second refresh runs before the first load does, so only the
    /// cancellation keeps the first stop's services off the card.
    @Test func `A new stop's services replace a load still running for the old one`() async throws {
        try mockService(id: "a", name: "Alpha Paratransit")
        try mockService(id: "b", name: "Bravo Flex")

        loader.refresh(for: try stop(ids: ["a"]), apiService: apiService)
        let first = try #require(loader.task)
        loader.refresh(for: try stop(ids: ["b"]), apiService: apiService)
        let second = try #require(loader.task)
        await first.value
        await second.value

        #expect(first.isCancelled)
        #expect(reports == [["Bravo Flex"]])
    }

    @Test func `Clearing reports an empty list and lets the same services load again`() async throws {
        try mockService(id: "a", name: "Alpha Paratransit")
        try await refresh(["a"])

        loader.clear()
        #expect(reports == [["Alpha Paratransit"], []])
        #expect(loader.task == nil)

        try await refresh(["a"])
        #expect(reports == [["Alpha Paratransit"], [], ["Alpha Paratransit"]])
        #expect(serviceRequests == 2)
    }

    /// The stop page clears the card when it leaves a flex stop mid-load.
    @Test func `Clearing during a load keeps its result off the card`() async throws {
        try mockService(id: "a", name: "Alpha Paratransit")
        loader.refresh(for: try stop(ids: ["a"]), apiService: apiService)
        let load = try #require(loader.task)

        loader.clear()
        await load.value

        #expect(reports == [[]])
    }
}
