//
//  LocationServiceAsyncStreamTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class LocationServiceAsyncStreamTests {
    private var createdDefaultsSuites: [String] = []

    private func freshDefaults() -> UserDefaults {
        let suiteName = "LocationServiceAsyncStreamTests.\(UUID().uuidString)"
        createdDefaultsSuites.append(suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    deinit {
        for suiteName in createdDefaultsSuites {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
    }

    private func makeService(
        autoDeliverOnStart: Bool = false,
        startsUpdatesOnAuthorization: Bool = false
    ) -> (AuthorizableLocationManagerMock, LocationService) {
        let mock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        if !autoDeliverOnStart {
            mock.updateLocation = nil
        }
        let service = LocationService(
            userDefaults: freshDefaults(),
            locationManager: mock,
            startsUpdatesOnAuthorization: startsUpdatesOnAuthorization
        )
        return (mock, service)
    }

    // MARK: - Stream Emission On Fix

    @Test func `Stream emission on fix`() async {
        let (_, service) = makeService()
        service.requestInUseAuthorization()

        let stream = service.locationStream()
        var iterator = stream.makeAsyncIterator()

        let firstFix = TestData.mockSeattleLocation
        service.locationManager(CLLocationManager(), didUpdateLocations: [firstFix])

        let receivedFirst = await iterator.next()
        #expect(receivedFirst == firstFix)
        #expect(service.currentLocation == firstFix)

        let secondFix = TestData.mockTampaLocation
        service.locationManager(CLLocationManager(), didUpdateLocations: [secondFix])

        let receivedSecond = await iterator.next()
        #expect(receivedSecond == secondFix)
        #expect(service.currentLocation == secondFix)
    }

    @Test func `Multiple stream subscribers both receive emitted fixes`() async {
        let (_, service) = makeService()
        service.requestInUseAuthorization()

        let stream1 = service.locationStream()
        let stream2 = service.locationStream()
        var iterator1 = stream1.makeAsyncIterator()
        var iterator2 = stream2.makeAsyncIterator()

        let fix = TestData.mockSeattleLocation
        service.locationManager(CLLocationManager(), didUpdateLocations: [fix])

        let received1 = await iterator1.next()
        let received2 = await iterator2.next()

        #expect(received1 == fix)
        #expect(received2 == fix)
    }

    // MARK: - Clean Cancellation On Termination

    @Test func `Clean cancellation on termination`() async {
        let (_, service) = makeService()
        service.requestInUseAuthorization()

        var receivedLocations: [CLLocation] = []
        let task = Task { @MainActor in
            for await location in service.locationStream() {
                receivedLocations.append(location)
            }
        }

        await poll(until: { service.locationStreamSubscriberCount == 1 }, "subscriber did not register")
        #expect(service.locationStreamSubscriberCount == 1)

        let fix = TestData.mockSeattleLocation
        service.locationManager(CLLocationManager(), didUpdateLocations: [fix])

        await poll(until: { receivedLocations.count == 1 }, "fix was not delivered to stream consumer")
        #expect(receivedLocations.first == fix)

        task.cancel()

        await poll(
            until: { service.locationStreamSubscriberCount == 0 },
            "subscriber was not cleaned up after task cancellation"
        )
        #expect(service.locationStreamSubscriberCount == 0)

        // Delivering a subsequent location does not reach cancelled consumer
        service.locationManager(CLLocationManager(), didUpdateLocations: [TestData.mockTampaLocation])
        await Task.yield()
        #expect(receivedLocations.count == 1)
    }

    // MARK: - Updates Halt When Subscribers Drop To Zero

    @Test func `Updates halt when subscribers drop to zero`() async {
        let (mock, service) = makeService(startsUpdatesOnAuthorization: false)
        mock.requestWhenInUseAuthorization()

        #expect(service.isLocationUseAuthorized)
        #expect(!mock.locationUpdatesStarted)
        #expect(!service.isUpdatingLocation)
        #expect(service.locationStreamSubscriberCount == 0)

        // First subscriber starts updates
        let stream1 = service.locationStream()
        let task1 = Task { @MainActor in
            for await _ in stream1 {}
        }

        await poll(until: { service.locationStreamSubscriberCount == 1 }, "first subscriber did not register")
        #expect(service.locationStreamSubscriberCount == 1)
        #expect(mock.locationUpdatesStarted)
        #expect(service.isUpdatingLocation)

        // Second subscriber joins; updates continue
        let stream2 = service.locationStream()
        let task2 = Task { @MainActor in
            for await _ in stream2 {}
        }

        await poll(until: { service.locationStreamSubscriberCount == 2 }, "second subscriber did not register")
        #expect(service.locationStreamSubscriberCount == 2)
        #expect(mock.locationUpdatesStarted)
        #expect(service.isUpdatingLocation)

        // Cancel first subscriber: updates remain running because subscriber count is 1
        task1.cancel()
        await poll(until: { service.locationStreamSubscriberCount == 1 }, "first subscriber cancellation not reflected")
        #expect(service.locationStreamSubscriberCount == 1)
        #expect(mock.locationUpdatesStarted)
        #expect(service.isUpdatingLocation)

        // Cancel second subscriber: subscriber count drops to zero, updates halt
        task2.cancel()
        await poll(until: { service.locationStreamSubscriberCount == 0 }, "subscribers did not drop to zero")
        #expect(service.locationStreamSubscriberCount == 0)
        #expect(!mock.locationUpdatesStarted)
        #expect(!service.isUpdatingLocation)
    }

    // MARK: - Authorization Lifecycle

    @Test func `Authorization grant with active subscriber starts updates`() async {
        let (mock, service) = makeService(startsUpdatesOnAuthorization: false)

        #expect(!service.isLocationUseAuthorized)
        #expect(!mock.locationUpdatesStarted)
        #expect(!service.isUpdatingLocation)

        let stream = service.locationStream()
        let task = Task { @MainActor in
            for await _ in stream {}
        }

        await poll(until: { service.locationStreamSubscriberCount == 1 }, "subscriber did not register")
        #expect(service.locationStreamSubscriberCount == 1)
        #expect(!mock.locationUpdatesStarted) // not authorized yet

        // Authorize now
        mock.requestWhenInUseAuthorization()

        #expect(service.isLocationUseAuthorized)
        #expect(mock.locationUpdatesStarted)
        #expect(service.isUpdatingLocation)

        task.cancel()
        await poll(until: { service.locationStreamSubscriberCount == 0 }, "subscriber did not terminate")
        #expect(!mock.locationUpdatesStarted)
        #expect(!service.isUpdatingLocation)
    }

    // MARK: - Stream Cancellation Does Not Stop Preexisting Updates

    @Test func `Stream cancellation preserves updates when updates were already running`() async {
        let (mock, service) = makeService(startsUpdatesOnAuthorization: false)
        mock.requestWhenInUseAuthorization()

        // Explicitly start continuous updates first
        service.startUpdatingLocation()
        #expect(service.isUpdatingLocation)
        #expect(mock.locationUpdatesStarted)

        // Subscribe to location stream
        let stream = service.locationStream()
        let task = Task { @MainActor in
            for await _ in stream {}
        }

        await poll(until: { service.locationStreamSubscriberCount == 1 }, "subscriber did not register")
        #expect(service.locationStreamSubscriberCount == 1)
        #expect(service.isUpdatingLocation)
        #expect(mock.locationUpdatesStarted)

        // Cancel subscriber: updates must continue running for the rest of the app
        task.cancel()
        await poll(until: { service.locationStreamSubscriberCount == 0 }, "subscriber did not terminate")
        #expect(service.locationStreamSubscriberCount == 0)
        #expect(service.isUpdatingLocation)
        #expect(mock.locationUpdatesStarted)

        // Explicit stop stops updates
        service.stopUpdatingLocation()
        #expect(!service.isUpdatingLocation)
        #expect(!mock.locationUpdatesStarted)
    }
}
