//
//  SearchViewModelDomainExtendedTests.swift
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

/// Extended domain tests for `SearchViewModel` result substituting,
/// vehicle loading states, and subtitle resolution.
@MainActor
@Suite(.serialized)
final class SearchViewModelDomainExtendedTests: OBATestCase {

    private func makeResponse(query: String = "44", results: [Any] = []) -> SearchResponse {
        SearchResponse(
            request: SearchRequest(query: query, type: .route),
            results: results,
            boundingRegion: nil,
            error: nil
        )
    }

    @Test func `SearchViewModel populates results and subtitle from searchResponse`() {
        let response = makeResponse(query: "RapidRide", results: ["item1", "item2"])
        let vm = SearchViewModel(searchResponse: response, apiService: nil)

        #expect(vm.results.count == 2)
        #expect(vm.subtitle == "Route RapidRide")
        #expect(vm.loadingVehicleID == nil)
        #expect(vm.failedVehicleID == nil)
    }

    @Test func `SearchViewModel substituting item creates updated SearchResponse`() {
        let response = makeResponse(query: "10", results: ["initial"])
        let vm = SearchViewModel(searchResponse: response, apiService: nil)

        let substituted = vm.response(substituting: "replacement")
        #expect(substituted.results.count == 1)
        #expect((substituted.results.first as? String) == "replacement")
    }

    @Test func `Select vehicle with nil apiService records network failure`() async {
        let response = makeResponse(query: "vehicle")
        let vm = SearchViewModel(searchResponse: response, apiService: nil)

        await vm.selectVehicle(vehicleID: "1_4351")

        #expect(vm.loadingVehicleID == nil)
        #expect(vm.vehicleError != nil)
        #expect(vm.failedVehicleID == "1_4351")
    }
}
