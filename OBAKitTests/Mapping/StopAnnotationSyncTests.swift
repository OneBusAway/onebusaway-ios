//
//  StopAnnotationSyncTests.swift
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

/// Pan used to add every newly fetched stop without removing ones that left
/// the viewport. MapKit then recycled annotation views and every pin flashed
/// to the default image. These tests fail if that extra-add returns.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/563
@Suite(.serialized)
struct StopAnnotationSyncTests {

    private let bookmarkA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let bookmarkB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    @Test func `A pan that returns the same stop IDs adds and removes nothing`() {
        let changes = StopAnnotationSync.changes(
            existingStopIDs: ["1", "2", "3"],
            existingBookmarks: [],
            incomingStopIDs: ["1", "2", "3"],
            bookmarksByStopID: [:],
            selectedStopIDs: [],
            isStopsLayerEnabled: true
        )

        #expect(changes.stopIDsToAdd.isEmpty)
        #expect(changes.stopIDsToRemove.isEmpty)
        #expect(changes.bookmarkIDsToAdd.isEmpty)
        #expect(changes.bookmarkIDsToRemove.isEmpty)
    }

    @Test func `A pan removes stops that left the viewport and adds only new IDs`() {
        let changes = StopAnnotationSync.changes(
            existingStopIDs: ["1", "2"],
            existingBookmarks: [],
            incomingStopIDs: ["2", "3"],
            bookmarksByStopID: [:],
            selectedStopIDs: [],
            isStopsLayerEnabled: true
        )

        #expect(changes.stopIDsToRemove == ["1"])
        #expect(changes.stopIDsToAdd == ["3"])
    }

    @Test func `A selected stop that left the viewport is not removed`() {
        let changes = StopAnnotationSync.changes(
            existingStopIDs: ["1", "2"],
            existingBookmarks: [],
            incomingStopIDs: ["3"],
            bookmarksByStopID: [:],
            selectedStopIDs: ["1"],
            isStopsLayerEnabled: true
        )

        #expect(!changes.stopIDsToRemove.contains("1"))
        #expect(changes.stopIDsToRemove == ["2"])
        #expect(changes.stopIDsToAdd == ["3"])
    }

    @Test func `A bookmark replaces the Stop annotation for that stop ID`() {
        let changes = StopAnnotationSync.changes(
            existingStopIDs: ["1"],
            existingBookmarks: [],
            incomingStopIDs: ["1"],
            bookmarksByStopID: ["1": bookmarkA],
            selectedStopIDs: [],
            isStopsLayerEnabled: true
        )

        #expect(changes.stopIDsToRemove == ["1"])
        #expect(changes.bookmarkIDsToAdd == [bookmarkA])
        #expect(changes.stopIDsToAdd.isEmpty)
    }

    @Test func `Stops layer off adds no Stop annotations and keeps bookmarks`() {
        let changes = StopAnnotationSync.changes(
            existingStopIDs: ["1"],
            existingBookmarks: [.init(id: bookmarkA, stopID: "2")],
            incomingStopIDs: ["1", "3"],
            bookmarksByStopID: ["2": bookmarkA],
            selectedStopIDs: [],
            isStopsLayerEnabled: false
        )

        #expect(changes.stopIDsToRemove == ["1"])
        #expect(changes.stopIDsToAdd.isEmpty)
        #expect(changes.bookmarkIDsToAdd.isEmpty)
        #expect(changes.bookmarkIDsToRemove.isEmpty)
    }
}
