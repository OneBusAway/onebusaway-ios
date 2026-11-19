//
//  StopArrivalsModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct StopArrivalsModelTests {

    private func makeStop() -> Stop {
        Stop(
            id: "1_100",
            name: "3rd & Pike",
            direction: "S",
            location: CLLocation(latitude: 47.6097, longitude: -122.3378)
        )
    }

    private func makeArrival() throws -> ArrivalDeparture {
        try Fixtures.loadRESTAPIPayload(
            type: ArrivalDeparture.self,
            fileName: "arrival-and-departure-for-stop-1_11420.json"
        )
    }

    @Test @MainActor func `Initial phase is loading`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        #expect(model.phase == .loading)
    }

    @Test @MainActor func `Missing API service transitions to failed immediately`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.startPolling()

        if case .failed(let message) = model.phase {
            #expect(message == Strings.noTransitRegion)
        } else {
            Issue.record("Expected failed phase when API service is nil, got \(model.phase)")
        }
    }

    @Test @MainActor func `Successful fetch with arrivals transitions to loaded`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))

        if case .loaded(let arrivals, _, let stale) = model.phase {
            #expect(arrivals.count == 1)
            #expect(stale == false)
        } else {
            Issue.record("Expected loaded phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Successful fetch with empty arrivals transitions to empty`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.success([]))

        if case .empty = model.phase {
            // Success
        } else {
            Issue.record("Expected empty phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Offline network error transitions to offline phase`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let offlineError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        model.apply(.failure(offlineError))

        #expect(model.phase == .offline)
    }

    @Test @MainActor func `Other error transitions to failed phase with message`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let serverError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server 500"])

        model.apply(.failure(serverError))

        if case .failed(let message) = model.phase {
            #expect(message == "Server 500")
        } else {
            Issue.record("Expected failed phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Failure when loaded preserves arrivals and marks stale`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        model.apply(.failure(error))

        if case .loaded(let arrivals, _, let stale) = model.phase {
            #expect(arrivals.count == 1)
            #expect(stale == true)
        } else {
            Issue.record("Expected loaded(stale: true), got \(model.phase)")
        }
    }

    @Test @MainActor func `Recovery after stale loaded phase restores fresh loaded state`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))
        model.apply(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))

        if case .loaded(_, _, let stale) = model.phase {
            #expect(stale == true)
        } else {
            Issue.record("Expected stale loaded phase")
        }

        // Subsequent poll succeeds
        model.apply(.success([arrival]))

        if case .loaded(let arrivals, _, let stale) = model.phase {
            #expect(arrivals.count == 1)
            #expect(stale == false)
        } else {
            Issue.record("Expected fresh loaded(stale: false) after recovery, got \(model.phase)")
        }
    }

    @Test @MainActor func `Recovery from offline to empty when poll returns no arrivals`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        #expect(model.phase == .offline)

        model.apply(.success([]))

        if case .empty = model.phase {
            // Success
        } else {
            Issue.record("Expected empty phase after recovering from offline, got \(model.phase)")
        }
    }

    @Test @MainActor func `Non-offline error while in empty phase leaves phase unchanged`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.success([]))
        if case .empty = model.phase {
            // expected
        } else {
            Issue.record("Expected empty phase")
        }

        // Server 500 error while in empty phase does not transition to offline or wipe empty state
        let serverError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        model.apply(.failure(serverError))

        if case .empty = model.phase {
            // expected to remain in empty
        } else {
            Issue.record("Expected empty phase to be preserved on non-offline failure, got \(model.phase)")
        }
    }

    @Test @MainActor func `Offline failure when empty transitions to offline`() {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)

        model.apply(.success([]))
        if case .empty = model.phase {
            // expected
        } else {
            Issue.record("Expected empty phase")
        }

        let offlineError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        model.apply(.failure(offlineError))

        #expect(model.phase == .offline)
    }

    @Test @MainActor func `Retry transitions to loading and restarts polling`() throws {
        let stop = makeStop()
        let service = RESTAPIService.standalone(
            region: Fixtures.pugetSoundRegion,
            apiKey: "key",
            appVersion: "1.0",
            uuid: "uuid"
        )
        let model = StopArrivalsModel(stop: stop, apiService: service)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))
        #expect(model.phase != .loading)

        model.retry()
        defer { model.stopPolling() }

        #expect(model.phase == .loading)
    }

    @Test @MainActor func `Retry without API service ends in failed`() throws {
        let stop = makeStop()
        let model = StopArrivalsModel(stop: stop, apiService: nil)
        let arrival = try makeArrival()

        model.apply(.success([arrival]))
        #expect(model.phase != .loading)

        model.retry()

        if case .failed(let message) = model.phase {
            #expect(message == Strings.noTransitRegion)
        } else {
            Issue.record("Expected failed after retry with nil apiService")
        }
    }
}
