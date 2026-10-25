//
//  RecentStopViewModelsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
struct RecentStopViewModelsTests {

    // MARK: - Helpers

    private func makeStop(
        id: String = "1_75403",
        name: String = "Stevens Way & Benton Ln",
        direction: String = "NE",
        routeType: Route.RouteType = .bus
    ) throws -> Stop {
        let stop = try Fixtures.loadSomeStops().first!
        let dictionary: [String: Any] = [
            "id": id,
            "name": name,
            "direction": direction,
            "lat": 47.6534,
            "lon": -122.3056,
            "code": "75403",
            "locationType": 0,
            "routeIds": ["1_100224"],
            "routes": [
                [
                    "id": "1_100224",
                    "shortName": "44",
                    "longName": "Montlake - Ballard",
                    "type": routeType.rawValue,
                    "agencyId": "1"
                ]
            ]
        ]
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dictionary)
    }

    // MARK: - StopRowItem Initialization & Content

    @Test func testStopRowItemInitializationWithoutDirectionInTitle() throws {
        let stop = try makeStop(name: "Pacific St & 15th Ave", direction: "W")
        let item = StopRowItem(withStop: stop, showDirectionInTitle: false, onSelect: nil, onDelete: nil)

        #expect(item.name == "Pacific St & 15th Ave")
        #expect(item.stopID == stop.id)
        #expect(item.routeType == stop.prioritizedRouteTypeForDisplay)
        #expect(item.subtitle == stop.subtitle)
        #expect(item.onSelectAction == nil)
        #expect(item.onDeleteAction == nil)
    }

    @Test func testStopRowItemInitializationWithDirectionInTitle() throws {
        let stop = try makeStop(name: "Pacific St & 15th Ave", direction: "W")
        let item = StopRowItem(withStop: stop, showDirectionInTitle: true, onSelect: nil, onDelete: nil)

        #expect(item.name == stop.nameWithLocalizedDirectionAbbreviation)
        #expect(item.name.contains("(W)"))
    }

    // MARK: - StopRowItem Row Configuration

    @Test func testStopRowItemConfiguration() throws {
        let stop = try makeStop(routeType: .bus)
        let item = StopRowItem(withStop: stop, onSelect: nil, onDelete: nil)

        guard case .custom(let obaConfig) = item.configuration,
              let rowConfig = obaConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom configuration")
            return
        }

        #expect(rowConfig.appearance == .subtitle)
        #expect(rowConfig.accessoryType == .disclosureIndicator)
        #expect(rowConfig.imageConfig.tintColor == nil)
        #expect(rowConfig.imageConfig.maximumSize == CGSize(width: Icons.squircleIconSize, height: Icons.squircleIconSize))

        if case .attributed(let styledTitle) = rowConfig.text {
            #expect(styledTitle.string == item.name)
            let attributes = styledTitle.attributes(at: 0, effectiveRange: nil)
            let font = attributes[.font] as? UIFont
            let color = attributes[.foregroundColor] as? UIColor
            #expect(font == UIFont.preferredFont(forTextStyle: .title3).bold)
            #expect(color == UIColor.label)
        } else {
            Issue.record("Expected .attributed text for title")
        }

        if let secondary = rowConfig.secondaryText {
            if case .attributed(let styledSubtitle) = secondary {
                #expect(styledSubtitle.string == stop.subtitle)
                let attributes = styledSubtitle.attributes(at: 0, effectiveRange: nil)
                let font = attributes[.font] as? UIFont
                let color = attributes[.foregroundColor] as? UIColor
                #expect(font == UIFont.preferredFont(forTextStyle: .body))
                #expect(color == UIColor.label)
            } else {
                Issue.record("Expected .attributed secondary text")
            }
        }
    }

    // MARK: - StopRowItem Actions & Equality

    @Test func testStopRowItemSelectAndDeleteActions() throws {
        let stop = try makeStop()
        var selectedItem: StopRowItem?
        var deletedItem: StopRowItem?

        let item = StopRowItem(
            withStop: stop,
            onSelect: { selectedItem = $0 },
            onDelete: { deletedItem = $0 }
        )

        item.onSelectAction?(item)
        #expect(selectedItem?.stopID == stop.id)

        item.onDeleteAction?(item)
        #expect(deletedItem?.stopID == stop.id)
    }

    @Test func testStopRowItemEqualityAndHashing() throws {
        let stop = try makeStop()
        let item1 = StopRowItem(withStop: stop, onSelect: nil, onDelete: nil)
        let item2 = StopRowItem(withStop: stop, onSelect: nil, onDelete: nil)

        #expect(item1 == item1)
        #expect(item1.hashValue == item1.hashValue)

        // Separate instances generate distinct UUIDs
        #expect(item1 != item2)
    }

    // MARK: - AlarmViewModel Tests

    @Test func testAlarmViewModelInitializationWithValidDeepLink() throws {
        let alarm = try Fixtures.loadAlarm()
        let deepLink = ArrivalDepartureDeepLink(
            title: "Route 44 - UW Station",
            regionID: 1,
            stopID: "1_75403",
            tripID: "trip_123",
            serviceDate: Date(timeIntervalSinceReferenceDate: 0),
            stopSequence: 3,
            vehicleID: "4321"
        )
        alarm.deepLink = deepLink

        var selectedAlarm: RecentStopsViewController.AlarmViewModel?
        var deletedAlarm: RecentStopsViewController.AlarmViewModel?

        let viewModel = RecentStopsViewController.AlarmViewModel(
            withAlarm: alarm,
            onSelect: { selectedAlarm = $0 },
            onDelete: { deletedAlarm = $0 }
        )

        let vm = try #require(viewModel)
        #expect(vm.title == "Route 44 - UW Station")
        #expect(vm.id == alarm.url)
        #expect(vm.alarm == alarm)
        #expect(vm.deepLink == deepLink)

        vm.onSelectAction?(vm)
        #expect(selectedAlarm?.id == alarm.url)

        vm.onDeleteAction?(vm)
        #expect(deletedAlarm?.id == alarm.url)
    }

    @Test func testAlarmViewModelInitializationFailsWhenDeepLinkNil() throws {
        let alarm = try Fixtures.loadAlarm()
        alarm.deepLink = nil

        let viewModel = RecentStopsViewController.AlarmViewModel(withAlarm: alarm, onSelect: nil, onDelete: nil)
        #expect(viewModel == nil)
    }

    @Test func testAlarmViewModelConfiguration() throws {
        let alarm = try Fixtures.loadAlarm()
        alarm.deepLink = ArrivalDepartureDeepLink(
            title: "Alarm Title",
            regionID: 1,
            stopID: "1_100",
            tripID: "trip_200",
            serviceDate: Date(timeIntervalSinceReferenceDate: 0),
            stopSequence: 1,
            vehicleID: nil
        )

        let viewModel = try #require(RecentStopsViewController.AlarmViewModel(withAlarm: alarm, onSelect: nil, onDelete: nil))

        guard case .custom(let obaConfig) = viewModel.configuration,
              let rowConfig = obaConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom configuration")
            return
        }

        #expect(rowConfig.text == .string("Alarm Title"))
        #expect(rowConfig.appearance == .subtitle)
        #expect(rowConfig.accessoryType == .disclosureIndicator)
    }

    @Test func testAlarmViewModelEqualityAndHashing() throws {
        let alarm1 = try Fixtures.loadAlarm(id: "alarm_1")
        let deepLink1 = ArrivalDepartureDeepLink(
            title: "Alarm 1",
            regionID: 1,
            stopID: "1_100",
            tripID: "trip_1",
            serviceDate: Date(timeIntervalSinceReferenceDate: 0),
            stopSequence: 1,
            vehicleID: nil
        )
        alarm1.deepLink = deepLink1

        let alarm2 = try Fixtures.loadAlarm(id: "alarm_2")
        let deepLink2 = ArrivalDepartureDeepLink(
            title: "Alarm 2",
            regionID: 1,
            stopID: "1_200",
            tripID: "trip_2",
            serviceDate: Date(timeIntervalSinceReferenceDate: 0),
            stopSequence: 2,
            vehicleID: nil
        )
        alarm2.deepLink = deepLink2

        let vm1 = try #require(RecentStopsViewController.AlarmViewModel(withAlarm: alarm1, onSelect: nil, onDelete: nil))
        let vm1Copy = try #require(RecentStopsViewController.AlarmViewModel(withAlarm: alarm1, onSelect: nil, onDelete: nil))
        let vm2 = try #require(RecentStopsViewController.AlarmViewModel(withAlarm: alarm2, onSelect: nil, onDelete: nil))

        #expect(vm1 == vm1Copy)
        #expect(vm1.hashValue == vm1Copy.hashValue)
        #expect(vm1 != vm2)
    }
}
