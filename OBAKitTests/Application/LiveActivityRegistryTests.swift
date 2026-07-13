//
//  LiveActivityRegistryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

/// Covers `LiveActivityRegistry`'s reconciliation sweep and unregistration, both of which have
/// to be careful about *when* a persisted delete URL may be forgotten: it's the only handle the
/// app has on the server-side subscription, so dropping it after a failed DELETE leaks the
/// subscription permanently.
class LiveActivityRegistryTests: OBATestCase {

    private let deadActivityID = "dead-activity"
    private let liveActivityID = "live-activity"

    private var deadDeleteURL: URL {
        URL(string: "https://alerts.example.com/api/v2/regions/1/live_activities/\(deadActivityID)")!
    }

    private var liveDeleteURL: URL {
        URL(string: "https://alerts.example.com/api/v2/regions/1/live_activities/\(liveActivityID)")!
    }

    private var dataLoader: MockDataLoader {
        // swiftlint:disable:next force_cast
        obacoService.dataLoader as! MockDataLoader
    }

    /// Builds a registry backed by the test's UserDefaults suite and mocked Obaco service.
    /// - parameter runningActivityIDs: Stands in for `Activity<TripAttributes>.activities`.
    private func buildRegistry(runningActivityIDs: Set<String>) -> LiveActivityRegistry {
        let service: ObacoAPIService = obacoService
        return LiveActivityRegistry(
            userDefaults: userDefaults,
            obacoServiceProvider: { service },
            runningActivityIDs: { runningActivityIDs }
        )
    }

    private func persistDeleteURLs(_ urls: [String: String]) {
        userDefaults.set(urls, forKey: LiveActivityRegistry.deleteURLsDefaultsKey)
    }

    private var persistedDeleteURLs: [String: String] {
        userDefaults.dictionary(forKey: LiveActivityRegistry.deleteURLsDefaultsKey) as? [String: String] ?? [:]
    }

    /// Mocks every DELETE to the live activities endpoint with the given status and records the
    /// URLs it saw.
    @discardableResult
    private func mockDeleteResponse(statusCode: Int) -> DeleteRecorder {
        let recorder = DeleteRecorder()
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            guard request.httpMethod == "DELETE", let url = request.url else { return false }
            recorder.record(url)
            return true
        }
        return recorder
    }

    /// Mocks every DELETE with a transport-level failure — no response at all, as if the device
    /// were offline.
    @discardableResult
    private func mockDeleteFailure(_ error: Error) -> DeleteRecorder {
        let recorder = DeleteRecorder()
        let response = MockDataResponse(data: nil, urlResponse: nil, error: error) { request in
            guard request.httpMethod == "DELETE", let url = request.url else { return false }
            recorder.record(url)
            return true
        }
        dataLoader.mock(response: response)
        return recorder
    }

    /// Thread-safe collector for the DELETEs a registry issued.
    private final class DeleteRecorder {
        private let lock = NSLock()
        private var _urls = [URL]()

        func record(_ url: URL) {
            lock.withLock { _urls.append(url) }
        }

        var urls: [URL] {
            lock.withLock { _urls }
        }
    }

    // MARK: - reconcile()

    /// The bug this type exists to fix: the user cleared a Live Activity while the app wasn't
    /// running, so nothing ever observed the dismissal and its delete URL was left behind. The
    /// activity is gone from ActivityKit, so the subscription must be deleted server-side.
    func testReconcileDeletesSubscriptionForActivityThatNoLongerExists() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertEqual(recorder.urls, [deadDeleteURL], "Expected reconcile() to DELETE the subscription for an activity that no longer exists.")
        XCTAssertTrue(persistedDeleteURLs.isEmpty, "Expected a confirmed DELETE to drop the persisted delete URL.")
    }

    /// A running activity still has (or will get) a lifecycle observer that unregisters it when
    /// it ends. Reconciliation must not touch it.
    func testReconcileLeavesStillRunningActivityAlone() async {
        persistDeleteURLs([liveActivityID: liveDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: [liveActivityID]).reconcile()

        XCTAssertTrue(recorder.urls.isEmpty, "Expected reconcile() to make no requests for an activity that is still running.")
        XCTAssertEqual(persistedDeleteURLs, [liveActivityID: liveDeleteURL.absoluteString], "Expected a still-running activity's delete URL to be retained.")
    }

    func testReconcileOnlySweepsTheDeadActivityWhenBothArePersisted() async {
        persistDeleteURLs([
            deadActivityID: deadDeleteURL.absoluteString,
            liveActivityID: liveDeleteURL.absoluteString
        ])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: [liveActivityID]).reconcile()

        XCTAssertEqual(recorder.urls, [deadDeleteURL])
        XCTAssertEqual(persistedDeleteURLs, [liveActivityID: liveDeleteURL.absoluteString])
    }

    /// The critical failure mode: if a flaky network let us forget the delete URL, the server-side
    /// subscription could never be deleted again. A transient failure must leave the entry in
    /// place so a later launch retries it.
    func testReconcileRetainsDeleteURLWhenTheDeviceIsOffline() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteFailure(URLError(.notConnectedToInternet))

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertEqual(recorder.urls, [deadDeleteURL])
        XCTAssertEqual(
            persistedDeleteURLs,
            [deadActivityID: deadDeleteURL.absoluteString],
            "Expected a transient DELETE failure to retain the persisted delete URL for a later retry."
        )
    }

    func testReconcileRetainsDeleteURLOnServerError() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteResponse(statusCode: 500)

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertEqual(
            persistedDeleteURLs,
            [deadActivityID: deadDeleteURL.absoluteString],
            "Expected a 500 to be treated as transient and retain the persisted delete URL."
        )
    }

    /// A retry that finds the row already deleted has nothing left to do, so the entry can go.
    func testReconcileForgetsDeleteURLWhenServerReports404() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteResponse(statusCode: 404)

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertTrue(persistedDeleteURLs.isEmpty, "Expected a 404 (the subscription is already gone) to drop the persisted delete URL.")
    }

    func testReconcileForgetsDeleteURLWhenServerReports410() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteResponse(statusCode: 410)

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertTrue(persistedDeleteURLs.isEmpty, "Expected a 410 Gone to drop the persisted delete URL.")
    }

    /// A malformed entry can never produce a request, so retaining it would just fail this check
    /// forever.
    func testReconcileDiscardsUnparseableDeleteURL() async {
        persistDeleteURLs([deadActivityID: ""])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertTrue(persistedDeleteURLs.isEmpty)
    }

    func testReconcileMakesNoRequestsWhenNothingIsPersisted() async {
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: []).reconcile()

        XCTAssertTrue(recorder.urls.isEmpty)
    }

    // MARK: - unregister()

    func testUnregisterDeletesSubscriptionAndForgetsItsURL() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: []).unregister(activityID: deadActivityID)

        XCTAssertEqual(recorder.urls, [deadDeleteURL])
        XCTAssertTrue(persistedDeleteURLs.isEmpty)
    }

    func testUnregisterRetainsDeleteURLWhenTheDeviceIsOffline() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteFailure(URLError(.timedOut))

        await buildRegistry(runningActivityIDs: []).unregister(activityID: deadActivityID)

        XCTAssertEqual(
            persistedDeleteURLs,
            [deadActivityID: deadDeleteURL.absoluteString],
            "Expected a transient DELETE failure to retain the persisted delete URL so reconcile() can retry it."
        )
    }

    func testUnregisterIsANoOpForAnUnknownActivity() async {
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(runningActivityIDs: []).unregister(activityID: "never-registered")

        XCTAssertTrue(recorder.urls.isEmpty)
    }

    // MARK: - Persistence contract

    /// The key and value shape are a field-persisted contract: delete URLs written by shipped
    /// builds must still be found (and cleaned up) by this code.
    func testRegistryReadsTheLegacyUserDefaultsKeyAndShape() {
        XCTAssertEqual(LiveActivityRegistry.deleteURLsDefaultsKey, "liveActivityDeleteURLs")

        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])

        let registry = buildRegistry(runningActivityIDs: [])
        XCTAssertEqual(registry.deleteURL(forActivityID: deadActivityID), deadDeleteURL)
    }
}
