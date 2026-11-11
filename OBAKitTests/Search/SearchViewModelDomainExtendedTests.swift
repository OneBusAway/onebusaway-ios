//
//  SearchViewModelDomainExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended domain tests for `SearchViewModel` query trimming, empty states,
/// and recent search item deduplication.
@MainActor
@Suite(.serialized)
final class SearchViewModelDomainExtendedTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test func `SearchViewModel trims whitespace around queries`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let vm = SearchViewModel(application: app)

        vm.query = "   44 Ballard   "
        #expect(vm.query == "   44 Ballard   ")
        #expect(vm.trimmedQuery == "44 Ballard")
    }

    @Test func `SearchViewModel trimmedQuery for empty or whitespace query is empty`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let vm = SearchViewModel(application: app)

        vm.query = ""
        #expect(vm.trimmedQuery.isEmpty)

        vm.query = "   \n\t  "
        #expect(vm.trimmedQuery.isEmpty)
    }

    @Test func `SearchViewModel isSearching reflects non-empty trimmed query`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let vm = SearchViewModel(application: app)

        vm.query = ""
        #expect(!vm.isSearching)

        vm.query = "   "
        #expect(!vm.isSearching)

        vm.query = "Metro"
        #expect(vm.isSearching)
    }
}
