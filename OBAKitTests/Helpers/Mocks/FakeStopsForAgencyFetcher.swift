//
//  FakeStopsForAgencyFetcher.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
@testable import OBAKitCore

/// A region's server for `RegionStopSyncService` tests. Records each call as it
/// starts, answers from `answers`, and can hold one agency's answer until the
/// test releases it.
actor FakeStopsForAgencyFetcher: StopsForAgencyFetching {
    private(set) var calls: [String] = []
    private(set) var isHolding = false

    private let agencyIDs: [String]
    private let maglev: Bool
    private var answers: [String: Result<StopsForAgencyResult, any Error>]
    private var heldAgency: String?
    private var heldCall: CheckedContinuation<Void, Never>?

    init(agencyIDs: [String], maglev: Bool = false, answers: [String: Result<StopsForAgencyResult, any Error>]) {
        self.agencyIDs = agencyIDs
        self.maglev = maglev
        self.answers = answers
    }

    func hold(agency: String) {
        heldAgency = agency
    }

    func release() {
        heldCall?.resume()
        heldCall = nil
    }

    func getAgencyIDs() async throws -> [String] {
        calls.append("agencies")
        return agencyIDs
    }

    func isMaglevServer() async throws -> Bool {
        calls.append("config")
        return maglev
    }

    func getStopsForAgency(id: String, ifNoneMatch etag: String?) async throws -> StopsForAgencyResult {
        calls.append(etag.map { "stops \(id) if-none-match \($0)" } ?? "stops \(id)")
        if heldAgency == id {
            heldAgency = nil
            isHolding = true
            await withCheckedContinuation { heldCall = $0 }
            isHolding = false
        }
        guard let answer = answers[id] else {
            throw APIError.requestNotFound(HTTPURLResponse(url: URL(string: "https://www.example.com")!, statusCode: 404, httpVersion: "2", headerFields: ["Content-Type": "application/json"])!)
        }
        return try answer.get()
    }
}
