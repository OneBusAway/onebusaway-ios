//
//  LiveActivityControlsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class LiveActivityControlsTests: OBATestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let staticData = TripAttributes.StaticData(
        routeShortName: "1 Line",
        routeHeadsign: "Downtown",
        stopID: "1_mtc",
        regionID: 1,
        tripID: ""
    )

    // MARK: - End Action

    @Test func `End handler invokes immediate dismissal and forwards regionID for target activity ID`() async {
        let recorded = SendableBox<(activityID: String, policy: ActivityUIDismissalPolicy)?>(nil)
        let didEnd = SendableBox<(activityID: String, regionID: Int)?>(nil)
        let expectedStaticData = staticData

        let handler = LiveActivityControlHandler(
            endActivity: { activityID, policy in
                recorded.value = (activityID, policy)
                return true
            },
            onDidEnd: { activityID, regionID in
                didEnd.value = (activityID, regionID)
            },
            loadStaticData: { _ in expectedStaticData },
            fetchStopArrivals: { _, _ in [] },
            updateActivity: { _, _, _ in false }
        )

        let result = await handler.end(activityID: "activity-42")

        #expect(result == .ended)
        #expect(recorded.value?.activityID == "activity-42")
        #expect(recorded.value?.policy == .immediate)
        #expect(didEnd.value?.activityID == "activity-42")
        #expect(didEnd.value?.regionID == expectedStaticData.regionID)
    }

    @Test func `End handler gracefully no-ops when activity ID is empty or missing`() async {
        let endCallCount = SendableBox(0)

        let handler = LiveActivityControlHandler(
            endActivity: { _, _ in
                endCallCount.value += 1
                return false
            },
            onDidEnd: { _, _ in
                Issue.record("onDidEnd should not be called when activity is missing")
            },
            loadStaticData: { _ in nil },
            fetchStopArrivals: { _, _ in [] },
            updateActivity: { _, _, _ in false }
        )

        #expect(await handler.end(activityID: "") == .notFound)
        #expect(endCallCount.value == 0)

        #expect(await handler.end(activityID: "missing-id") == .notFound)
        #expect(endCallCount.value == 1)
    }

    @Test func `End handler unregisters using activity staticData regionID when store holds another region`() async throws {
        // Store currently points to a custom region without an Obaco sidecar, while the ended
        // Live Activity belongs to Puget Sound (region 1).
        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.customMinneapolisRegion)
        let regionsBundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("regions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: regionsBundleURL) }
        try Fixtures.loadData(file: "regions-v3.json").write(to: regionsBundleURL)

        let pugetSoundSidecar = try #require(Fixtures.pugetSoundRegion.sidecarBaseURL)
        let activityID = "activity-puget-sound"
        let deleteURLString = pugetSoundSidecar
            .appendingPathComponent("api/v1/regions/1/live_activities/\(activityID)")
            .absoluteString
        userDefaults.set([activityID: deleteURLString], forKey: LiveActivityRegistry.deleteURLsDefaultsKey)
        let registry = LiveActivityRegistry(userDefaults: userDefaults, obacoServiceProvider: { nil })

        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Data()) { request in
            request.httpMethod == "DELETE"
                && request.url?.absoluteString == deleteURLString
        }

        let handler = LiveActivityControlHandler(
            appGroupIdentifier: userDefaultsSuiteName,
            bundledRegionsFilePath: regionsBundleURL.path,
            restServerAPIKey: apiKey,
            appVersion: appVersion,
            dataLoader: dataLoader,
            endActivity: { _, _ in true },
            loadStaticData: { [staticData] id in id == activityID ? staticData : nil }
        )

        let result = await handler.end(activityID: activityID)

        #expect(result == .ended)
        #expect(dataLoader.recordedRequestURLs.count == 1)
        #expect(dataLoader.recordedRequestURLs.first?.absoluteString == deleteURLString)
        #expect(registry.deleteURL(forActivityID: activityID) == nil)
    }

    @Test func `Non-bundled regionID differing from stored region does not fall back to stored region`() async throws {
        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.pugetSoundRegion)
        let regionsBundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("regions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: regionsBundleURL) }
        try Fixtures.loadData(file: "regions-v3.json").write(to: regionsBundleURL)

        let customRegionID = 999_999
        let resolved = LiveActivityControlHandler.resolveRegion(
            regionID: customRegionID,
            userDefaults: userDefaults,
            bundledRegionsFilePath: regionsBundleURL.path
        )
        #expect(resolved == nil)

        let customStaticData = TripAttributes.StaticData(
            routeShortName: "1 Line",
            routeHeadsign: "Downtown",
            stopID: "99_stop",
            regionID: customRegionID
        )
        let activityID = "activity-custom-region"
        let deleteURLString = "https://custom-sidecar.example.com/api/v1/regions/\(customRegionID)/live_activities/\(activityID)"
        userDefaults.set([activityID: deleteURLString], forKey: LiveActivityRegistry.deleteURLsDefaultsKey)
        let registry = LiveActivityRegistry(userDefaults: userDefaults, obacoServiceProvider: { nil })

        let dataLoader = MockDataLoader(testName: name)
        let handler = LiveActivityControlHandler(
            appGroupIdentifier: userDefaultsSuiteName,
            bundledRegionsFilePath: regionsBundleURL.path,
            restServerAPIKey: apiKey,
            appVersion: appVersion,
            dataLoader: dataLoader,
            endActivity: { _, _ in true },
            loadStaticData: { id in id == activityID ? customStaticData : nil },
            updateActivity: { _, _, _ in true }
        )

        #expect(await handler.refresh(activityID: activityID) == .missingConfiguration)
        #expect(dataLoader.recordedRequestURLs.isEmpty)

        #expect(await handler.end(activityID: activityID) == .ended)
        #expect(dataLoader.recordedRequestURLs.isEmpty)
        #expect(registry.deleteURL(forActivityID: activityID)?.absoluteString == deleteURLString)
    }

    // MARK: - Refresh Action

    private struct AppliedUpdate: Equatable {
        let activityID: String
        let state: TripAttributes.ContentState
        let staleDate: Date?
    }

    @Test func `Refresh handler loads departures and updates ContentState and staleDate`() async throws {
        let arrivals = try [
            makeArrival(routeShortName: "1 Line", headsign: "Downtown", tripID: "trip_past", departureDate: now.addingTimeInterval(-120)),
            makeArrival(routeShortName: "1 Line", headsign: "Airport", tripID: "trip_other_dir", departureDate: now.addingTimeInterval(180)),
            makeArrival(routeShortName: "1 Line", headsign: "Downtown", tripID: "trip_2", departureDate: now.addingTimeInterval(900)),
            makeArrival(routeShortName: "1 Line", headsign: "Downtown", tripID: "trip_1", departureDate: now.addingTimeInterval(300), deviationMinutes: 2),
        ]

        let applied = SendableBox<AppliedUpdate?>(nil)
        let fetchedStop = SendableBox<(stopID: String, regionID: Int)?>(nil)

        let handler = LiveActivityControlHandler(
            endActivity: { _, _ in false },
            loadStaticData: { [staticData] id in id == "activity-1" ? staticData : nil },
            fetchStopArrivals: { stopID, regionID in
                fetchedStop.value = (stopID, regionID)
                return arrivals
            },
            updateActivity: { activityID, state, staleDate in
                applied.value = AppliedUpdate(activityID: activityID, state: state, staleDate: staleDate)
                return true
            },
            staleInterval: 300,
            now: { [now] in now }
        )

        let result = await handler.refresh(activityID: "activity-1")

        let expectedState = TripAttributes.ContentState(arrivals: [
            .init(departureTime: Int(now.addingTimeInterval(300).timeIntervalSince1970), scheduleStatus: .delayed, scheduleDeviation: 120, isArrival: false),
            .init(departureTime: Int(now.addingTimeInterval(900).timeIntervalSince1970), scheduleStatus: .onTime, scheduleDeviation: 0, isArrival: false),
        ])
        let expectedStaleDate = now.addingTimeInterval(300)

        #expect(result == .updated(expectedState, staleDate: expectedStaleDate))
        #expect(fetchedStop.value?.stopID == "1_mtc")
        #expect(fetchedStop.value?.regionID == 1)
        #expect(applied.value == AppliedUpdate(activityID: "activity-1", state: expectedState, staleDate: expectedStaleDate))
    }

    @Test func `Refresh handler pins matching tripID when present`() async throws {
        let pinnedStaticData = TripAttributes.StaticData(
            routeShortName: "1 Line",
            routeHeadsign: "Downtown",
            stopID: "1_mtc",
            regionID: 1,
            tripID: "trip_pinned"
        )
        let earlier = try makeArrival(
            routeShortName: "1 Line",
            headsign: "Downtown",
            tripID: "trip_earlier",
            departureDate: now.addingTimeInterval(180)
        )
        let pinned = try makeArrival(
            routeShortName: "1 Line",
            headsign: "Downtown",
            tripID: "trip_pinned",
            departureDate: now.addingTimeInterval(600)
        )

        let handler = LiveActivityControlHandler(
            endActivity: { _, _ in false },
            loadStaticData: { _ in pinnedStaticData },
            fetchStopArrivals: { _, _ in [earlier, pinned] },
            updateActivity: { _, _, _ in true },
            staleInterval: 300,
            now: { [now] in now }
        )

        let result = await handler.refresh(activityID: "activity-pinned")

        guard case .updated(let state, _) = result else {
            Issue.record("Expected updated result, got \(result)")
            return
        }
        #expect(state.arrivals.count == 1)
        #expect(state.arrivals[0].departureTime == Int(now.addingTimeInterval(600).timeIntervalSince1970))
    }

    @Test func `Refresh handler gracefully no-ops on missing activity or fetch failure`() async {
        enum SampleError: Error { case offline }

        let updateCallCount = SendableBox(0)

        let missingHandler = LiveActivityControlHandler(
            endActivity: { _, _ in false },
            loadStaticData: { _ in nil },
            fetchStopArrivals: { _, _ in
                Issue.record("Should not fetch arrivals when activity is missing")
                return []
            },
            updateActivity: { _, _, _ in
                updateCallCount.value += 1
                return true
            }
        )

        #expect(await missingHandler.refresh(activityID: "unknown") == .notFound)
        #expect(await missingHandler.refresh(activityID: "") == .notFound)
        #expect(updateCallCount.value == 0)

        let failingHandler = LiveActivityControlHandler(
            endActivity: { _, _ in false },
            loadStaticData: { [staticData] _ in staticData },
            fetchStopArrivals: { _, _ in throw SampleError.offline },
            updateActivity: { _, _, _ in
                updateCallCount.value += 1
                return true
            }
        )

        #expect(await failingHandler.refresh(activityID: "activity-1") == .failed)
        #expect(updateCallCount.value == 0)
    }

    @Test func `Refresh handler leaves activity untouched when no matching upcoming arrivals exist`() async throws {
        let pastMatching = try makeArrival(
            routeShortName: "1 Line",
            headsign: "Downtown",
            tripID: "trip_past",
            departureDate: now.addingTimeInterval(-60)
        )
        let otherRouteUpcoming = try makeArrival(
            routeShortName: "2 Line",
            headsign: "Downtown",
            tripID: "trip_other_route",
            departureDate: now.addingTimeInterval(300)
        )
        let updateCallCount = SendableBox(0)

        let handler = LiveActivityControlHandler(
            endActivity: { _, _ in false },
            loadStaticData: { [staticData] _ in staticData },
            fetchStopArrivals: { _, _ in [pastMatching, otherRouteUpcoming] },
            updateActivity: { _, _, _ in
                updateCallCount.value += 1
                return true
            },
            now: { [now] in now }
        )

        let result = await handler.refresh(activityID: "activity-1")

        #expect(result == .noMatchingArrivals)
        #expect(updateCallCount.value == 0)
    }

    @Test func `Widget-configured handler fetches REST arrivals and handles missing API key`() async throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals_and_departures_for_stop_1_29261.json")
        let firstArrival = try #require(stopArrivals.arrivalsAndDepartures.first)
        let fixtureStaticData = TripAttributes.StaticData(
            routeShortName: firstArrival.routeShortName,
            routeHeadsign: firstArrival.tripHeadsign ?? "",
            stopID: "1_29261",
            regionID: Fixtures.pugetSoundRegion.regionIdentifier
        )
        let fixedNow = firstArrival.arrivalDepartureDate.addingTimeInterval(-120)

        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.pugetSoundRegion)
        let dataLoader = MockDataLoader(testName: name)
        let fixtureData = Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_29261.json")
        dataLoader.mock(data: fixtureData) { request in
            request.url?.path.contains("arrivals-and-departures-for-stop/1_29261.json") == true
        }

        let missingKeyHandler = LiveActivityControlHandler(
            appGroupIdentifier: userDefaultsSuiteName,
            bundledRegionsFilePath: nil,
            restServerAPIKey: nil,
            appVersion: appVersion,
            dataLoader: dataLoader,
            now: { fixedNow },
            loadStaticData: { _ in fixtureStaticData },
            updateActivity: { _, _, _ in true }
        )
        #expect(await missingKeyHandler.refresh(activityID: "act-1") == .missingConfiguration)
        #expect(dataLoader.recordedRequestURLs.isEmpty)

        let updatedState = SendableBox<TripAttributes.ContentState?>(nil)
        let liveHandler = LiveActivityControlHandler(
            appGroupIdentifier: userDefaultsSuiteName,
            bundledRegionsFilePath: nil,
            restServerAPIKey: apiKey,
            appVersion: appVersion,
            dataLoader: dataLoader,
            staleInterval: 300,
            now: { fixedNow },
            loadStaticData: { _ in fixtureStaticData },
            updateActivity: { _, state, _ in updatedState.value = state; return true }
        )

        let result = await liveHandler.refresh(activityID: "act-1")
        guard case .updated(let state, let staleDate) = result else {
            Issue.record("Expected updated result, got \(result)")
            return
        }
        #expect(!state.arrivals.isEmpty)
        #expect(staleDate == fixedNow.addingTimeInterval(300))
        #expect(updatedState.value == state)
        #expect(dataLoader.recordedRequestURLs.count == 1)
    }

    // MARK: - AppIntents Metadata & Localization

    @Test func `App and Widget AppIntents metadata registers non-launching LiveActivityIntents`() throws {
        let appActionsDataURL = Bundle.main.bundleURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        let widgetPluginURL = try #require(
            Bundle.main.builtInPlugInsURL?.appendingPathComponent("OBAWidget.appex"),
            "Expected embedded OBAWidget.appex in test host bundle"
        )
        let widgetActionsDataURL = widgetPluginURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")

        for (label, actionsDataURL) in [("App", appActionsDataURL), ("OBAWidget", widgetActionsDataURL)] {
            try #require(
                FileManager.default.fileExists(atPath: actionsDataURL.path),
                "Missing \(label) Metadata.appintents/extract.actionsdata at \(actionsDataURL.path)"
            )
            let data = try Data(contentsOf: actionsDataURL)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let actions = json["actions"] as? [String: Any] ?? [:]

            for intentName in ["EndLiveActivityIntent", "RefreshLiveActivityIntent"] {
                let metadata = try #require(actions[intentName] as? [String: Any], "Missing \(intentName) in \(label) Metadata.appintents")
                let isDiscoverable = metadata["isDiscoverable"] as? Bool ?? true
                #expect(!isDiscoverable, "\(intentName) in \(label) should not be discoverable in Shortcuts")
                let openAppWhenRun = metadata["openAppWhenRun"] as? Bool ?? false
                #expect(!openAppWhenRun, "\(intentName) in \(label) must keep openAppWhenRun == false")
            }
        }
    }

    // MARK: - Card Rendering

    @Test func `TripLiveActivityCardView renders with and without controls within Lock Screen height`() {
        let state = TestData.buildActivityContentState(
            departureOffsets: [600, 1500, 2400],
            baseTimestamp: Int(Date().timeIntervalSince1970)
        )

        let plainCard = TripLiveActivityCardView(
            staticData: staticData,
            contentState: state,
            isStale: true,
            showsDismissHint: false
        )
        let plainSize = UIHostingController(rootView: plainCard)
            .sizeThatFits(in: CGSize(width: 370, height: 1000))
        #expect(plainSize.height > 0)
        #expect(plainSize.height <= 160)

        let cardWithControls = TripLiveActivityCardView(
            staticData: staticData,
            contentState: state,
            isStale: true,
            showsDismissHint: false
        ) {
            HStack(spacing: 6) {
                Button(LiveActivityControlHandler.refreshTitle) {}
                    .font(.caption2.weight(.semibold))
                Button(LiveActivityControlHandler.endTitle) {}
                    .font(.caption2.weight(.semibold))
            }
        }
        let controlsSize = UIHostingController(rootView: cardWithControls)
            .sizeThatFits(in: CGSize(width: 370, height: 1000))
        #expect(controlsSize.height > 0)
        #expect(controlsSize.height <= 160)
    }

    // MARK: - Fixtures

    private func makeArrival(
        routeShortName: String,
        headsign: String,
        tripID: String,
        departureDate: Date,
        deviationMinutes: Int = 0,
        predicted: Bool = true
    ) throws -> ArrivalDeparture {
        let scheduled = departureDate.addingTimeInterval(TimeInterval(-deviationMinutes * 60))
        let scheduledSeconds = scheduled.timeIntervalSinceReferenceDate
        let predictedSeconds = departureDate.timeIntervalSinceReferenceDate

        var dictionary: [String: Any] = [
            "arrivalEnabled": false,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": scheduledSeconds,
            "numberOfStopsAway": 2,
            "predicted": predicted,
            "routeId": "1_100",
            "routeShortName": routeShortName,
            "scheduledArrivalTime": scheduledSeconds,
            "scheduledDepartureTime": scheduledSeconds,
            "serviceDate": scheduledSeconds,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "1_mtc",
            "stopSequence": 0,
            "tripHeadsign": headsign,
            "tripId": tripID,
            "vehicleId": "1_veh"
        ]
        if predicted {
            dictionary["predictedArrivalTime"] = predictedSeconds
            dictionary["predictedDepartureTime"] = predictedSeconds
        }

        let arrivalDeparture = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dictionary)
        let references = try Fixtures.dictionaryToModel(
            type: References.self,
            dictionary: makeReferencesData(routeShortName: routeShortName, tripID: tripID)
        )
        arrivalDeparture.loadReferences(references, regionIdentifier: 1)
        return arrivalDeparture
    }

    private func makeReferencesData(routeShortName: String, tripID: String) -> [String: Any] {
        [
            "agencies": [[
                "id": "1",
                "name": "Test Agency",
                "url": "https://example.com",
                "timezone": "America/Los_Angeles",
                "lang": "en",
                "phone": "555-0123",
                "privateService": false
            ]],
            "routes": [[
                "id": "1_100",
                "agencyId": "1",
                "shortName": routeShortName,
                "type": 3
            ]],
            "stops": [[
                "id": "1_mtc",
                "code": "mtc",
                "name": "Transit Center",
                "lat": 47.6097,
                "lon": -122.3331,
                "locationType": 0,
                "routeIds": ["1_100"]
            ]],
            "trips": [[
                "id": tripID,
                "blockId": "block_\(tripID)",
                "routeId": "1_100",
                "serviceId": "service_1",
                "routeShortName": routeShortName,
                "tripShortName": "Trip",
                "timeZone": "America/Los_Angeles"
            ]]
        ]
    }
}
