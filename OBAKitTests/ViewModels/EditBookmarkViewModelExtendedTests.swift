//
//  EditBookmarkViewModelExtendedTests.swift
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

@Suite(.serialized)
final class EditBookmarkViewModelExtendedTests: OBATestCase {

    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func createApplication(dataLoader: MockDataLoader? = nil) -> Application {
        let loader = dataLoader ?? MockDataLoader(testName: name)
        return buildApplication(queue: queue, dataLoader: loader)
    }

    private func createApplicationWithoutRegion(dataLoader: MockDataLoader? = nil) -> Application {
        let loader = dataLoader ?? MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        stubAgenciesWithCoverage(dataLoader: loader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: loader
        )
        return Application(config: config)
    }

    private func makeStop(id: String = "stop_edit_1", name: String = "4th & Pike") throws -> Stop {
        let stopData: [String: Any] = [
            "id": id,
            "name": name,
            "lat": 47.61,
            "lon": -122.33,
            "direction": "NB",
            "code": "101",
            "locationType": 0,
            "routeIds": ["route_10"]
        ]
        let stop = try Fixtures.dictionaryToModel(type: Stop.self, dictionary: stopData)
        let references = References(agencies: [], routes: [], situations: [], stops: [stop], trips: [])
        stop.loadReferences(references, regionIdentifier: 1)
        return stop
    }

    private func makeArrivalDeparture(stop: Stop, routeShortName: String = "10", headsign: String = "Downtown") throws -> ArrivalDeparture {
        let arrDepData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 300.0,
            "lastUpdateTime": 1600000000,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_10",
            "scheduledArrivalTime": 1600000600,
            "scheduledDepartureTime": 1600000600,
            "serviceDate": 1600000000,
            "situationIds": [],
            "status": "default",
            "stopId": stop.id,
            "stopSequence": 2,
            "tripId": "trip_100",
            "vehicleId": "veh_10"
        ]
        let routeData: [String: Any] = [
            "id": "route_10",
            "agencyId": "1",
            "shortName": routeShortName,
            "longName": "Route \(routeShortName)",
            "type": 3
        ]
        let tripData: [String: Any] = [
            "id": "trip_100",
            "blockId": "block_1",
            "routeId": "route_10",
            "routeShortName": routeShortName,
            "tripHeadsign": headsign,
            "tripShortName": "100",
            "serviceId": "s1",
            "timeZone": "America/Los_Angeles",
            "directionId": "0"
        ]

        let arrival = try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrDepData)
        let route = try Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        let trip = try Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)

        let references = References(agencies: [], routes: [route], situations: [], stops: [stop], trips: [trip])
        arrival.loadReferences(references, regionIdentifier: 1)
        return arrival
    }

    @Test @MainActor func `Add group ignores empty and whitespace-only strings`() throws {
        let app = createApplication()
        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        let initialCount = vm.groups.count
        vm.addGroup(named: "")
        vm.addGroup(named: "   ")
        vm.addGroup(named: "\t\n  ")

        #expect(vm.groups.count == initialCount)
        #expect(app.userDataStore.bookmarkGroups.count == initialCount)
    }

    @Test @MainActor func `Add group trims whitespace and appends group`() throws {
        let app = createApplication()
        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        vm.addGroup(named: "  Commute Routes  ")

        #expect(vm.groups.contains { $0.name == "Commute Routes" })
        #expect(app.userDataStore.bookmarkGroups.contains { $0.name == "Commute Routes" })
    }

    @Test @MainActor func `Resolve duplicate cancelled is a no-op`() throws {
        let app = createApplication()
        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        let initialBookmarkCount = app.userDataStore.bookmarks.count
        vm.resolveDuplicate(.cancelled, name: "Cancelled Name", isFavorite: true, to: nil)

        #expect(app.userDataStore.bookmarks.count == initialBookmarkCount)
    }

    @Test @MainActor func `Resolve duplicate createDuplicate writes bookmark to data store`() throws {
        let app = createApplication()
        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)

        let bookmarkToDuplicate = Bookmark(name: "Orig Bookmark", regionIdentifier: 1, stop: stop)
        let group = BookmarkGroup(name: "Weekend", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)

        vm.resolveDuplicate(
            .createDuplicate(bookmarkToDuplicate),
            name: "Duplicate Name",
            isFavorite: false,
            to: group.id
        )

        let saved = try #require(app.userDataStore.findBookmark(id: bookmarkToDuplicate.id))
        #expect(saved.name == "Duplicate Name")
        #expect(saved.isFavorite == false)
        #expect(saved.groupID == group.id)
    }

    @Test @MainActor func `PrepareToSave returns regionUnavailable when currentRegion is nil`() throws {
        let app = createApplicationWithoutRegion()

        let stop = try makeStop()
        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: nil)
        let outcome = vm.prepareToSave(name: "Home Stop")

        guard case .regionUnavailable = outcome else {
            Issue.record("Expected .regionUnavailable, got \(outcome)")
            return
        }
    }

    @Test @MainActor func `PrepareToSave in edit mode always returns readyToSaveExisting`() throws {
        let app = createApplication()
        let stop = try makeStop()
        let existing = Bookmark(name: "Existing Stop", regionIdentifier: 1, stop: stop)
        app.userDataStore.add(bookmark: existing)

        let vm = EditBookmarkViewModel(application: app, source: .stop(stop), bookmark: existing)
        let outcome = vm.prepareToSave(name: "Updated Name")

        guard case .readyToSaveExisting(let b) = outcome else {
            Issue.record("Expected .readyToSaveExisting, got \(outcome)")
            return
        }
        #expect(b.id == existing.id)
    }

    @Test @MainActor func `Set destination updates destinationStop and re-resolves default name`() throws {
        let app = createApplication()
        let boardingStop = try makeStop(id: "stop_board", name: "Pine St & 4th Ave")
        let destStop = try makeStop(id: "stop_dest", name: "Main St & 2nd Ave")
        let arrDep = try makeArrivalDeparture(stop: boardingStop, routeShortName: "10", headsign: "Downtown")

        let vm = EditBookmarkViewModel(application: app, source: .arrivalDeparture(arrDep), bookmark: nil)
        #expect(vm.canChooseDestination == true)

        vm.setDestination(destStop)
        #expect(vm.destinationStop?.id == destStop.id)
        #expect(vm.destinationName == "Main St & 2nd Ave")
        #expect(vm.name.contains("Main St & 2nd Ave"))

        // Clearing destination
        vm.setDestination(nil)
        #expect(vm.destinationStop == nil)
        #expect(vm.destinationName == nil)
    }
}
