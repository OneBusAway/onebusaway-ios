//
//  BookmarkDestinationStatusTests.swift
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
final class BookmarkDestinationStatusTests: OBATestCase {

    // MARK: - Discrete Case Discrimination

    @Test func `Loading and notServed status cases compare equal to themselves`() {
        let statusA: BookmarkDestinationStatus = .loading
        let statusB: BookmarkDestinationStatus = .loading
        let statusC: BookmarkDestinationStatus = .notServed

        #expect(statusA == statusB)
        #expect(statusA != statusC)
    }

    // MARK: - Arrives Equality

    @Test func `Arrives case equality is determined by underlying DestinationArrival`() {
        let date1 = Date(timeIntervalSince1970: 1700000000)
        let date2 = Date(timeIntervalSince1970: 1700000600)

        let arrival1 = DestinationArrival(destinationArrivalTime: date1, tripHeadsign: "Downtown")
        let arrival2 = DestinationArrival(destinationArrivalTime: date1, tripHeadsign: "Downtown")
        let arrival3 = DestinationArrival(destinationArrivalTime: date2, tripHeadsign: "Downtown")

        let status1 = BookmarkDestinationStatus.arrives(arrival1)
        let status2 = BookmarkDestinationStatus.arrives(arrival2)
        let status3 = BookmarkDestinationStatus.arrives(arrival3)

        #expect(status1 == status2)
        #expect(status1 != status3)
        #expect(status1 != .loading)
        #expect(status1 != .notServed)
    }

    // MARK: - Section Identifiers

    @Test func `BookmarkListSection preserves identifiers and titles`() {
        let section = BookmarkListSection(
            id: "distance_sorted_group",
            title: "Nearby Bookmarks",
            rows: []
        )

        #expect(section.id == "distance_sorted_group")
        #expect(section.title == "Nearby Bookmarks")
        #expect(section.rows.isEmpty)
    }
}
