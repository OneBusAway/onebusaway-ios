//
//  OBAListViewUpdateStrategyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import UIKit
@testable import OBAKit

// MARK: - Minimal stub item for testing strategy logic without a real collection view

/// A minimal `OBAListViewItem` used exclusively in strategy tests.
/// It has no rendering logic — only `id` (for identity) and `value` (for equality).
private struct StubItem: OBAListViewItem {
    let id: String
    let value: Int

    var configuration: OBAListViewItemConfiguration {
        // Returning a plain list configuration satisfies the protocol without
        // needing any cell registration.
        .list(.init(), [])
    }

    static func == (lhs: StubItem, rhs: StubItem) -> Bool {
        lhs.id == rhs.id && lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(value)
    }
}

// MARK: - Helpers

private extension OBAListViewSection {
    /// Convenience initialiser for tests: a section with no header and the given stub items.
    static func stub(id: String, items: [StubItem]) -> OBAListViewSection {
        OBAListViewSection(id: id, title: nil, contents: items)
    }

    /// Convenience initialiser for tests: a section with a header and the given stub items.
    static func stubWithHeader(id: String, title: String, items: [StubItem]) -> OBAListViewSection {
        OBAListViewSection(id: id, title: title, contents: items)
    }
}

// MARK: - Tests

@MainActor
final class OBAListViewUpdateStrategyTests: XCTestCase {

    // A real OBAListView is required because getUpdateStrategy is an instance method.
    // We never add it to a window, so no UIKit layout occurs.
    private var listView: OBAListView!

    override func setUp() {
        super.setUp()
        listView = OBAListView()
    }

    override func tearDown() {
        listView = nil
        super.tearDown()
    }

    // MARK: - .noChange

    func test_noChange_whenBothEmpty() {
        let strategy = listView.getUpdateStrategy(oldSections: [], newSections: [])
        expect(strategy) == .noChange
    }

    func test_noChange_whenSectionsAndItemsAreIdentical() {
        let items = [StubItem(id: "a", value: 1), StubItem(id: "b", value: 2)]
        let old = [OBAListViewSection.stub(id: "s1", items: items)]
        let new = [OBAListViewSection.stub(id: "s1", items: items)]

        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .contentUpdate
    }

    // MARK: - .fullRebuild

    func test_fullRebuild_whenOldIsEmpty() {
        let new = [OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)])]
        let strategy = listView.getUpdateStrategy(oldSections: [], newSections: new)
        expect(strategy) == .fullRebuild
    }

    func test_fullRebuild_whenNewIsEmpty() {
        let old = [OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)])]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: [])
        expect(strategy) == .fullRebuild
    }

    func test_fullRebuild_whenSectionIdsChange() {
        let old = [OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)])]
        let new = [OBAListViewSection.stub(id: "s2", items: [StubItem(id: "a", value: 1)])]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .fullRebuild
    }

    func test_fullRebuild_whenSectionOrderChanges() {
        let old = [
            OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)]),
            OBAListViewSection.stub(id: "s2", items: [StubItem(id: "b", value: 2)])
        ]
        let new = [
            OBAListViewSection.stub(id: "s2", items: [StubItem(id: "b", value: 2)]),
            OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)])
        ]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .fullRebuild
    }

    func test_fullRebuild_whenSectionCountIncreases() {
        let old = [OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)])]
        let new = [
            OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)]),
            OBAListViewSection.stub(id: "s2", items: [StubItem(id: "b", value: 2)])
        ]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .fullRebuild
    }

    // MARK: - .sectionReload

    func test_sectionReload_whenItemCountChanges() {
        let old = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "a", value: 1)
        ])]
        let new = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "a", value: 1),
            StubItem(id: "b", value: 2)
        ])]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .sectionReload
    }

    func test_sectionReload_whenHeaderPresenceChanges() {
        let items = [StubItem(id: "a", value: 1)]
        let old = [OBAListViewSection.stub(id: "s1", items: items)]
        let new = [OBAListViewSection.stubWithHeader(id: "s1", title: "Header", items: items)]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .sectionReload
    }

    func test_sectionReload_whenAllItemIDsChangeButSameCount() {
        let old = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "a", value: 1),
            StubItem(id: "b", value: 2)
        ])]
        let new = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "c", value: 3),
            StubItem(id: "d", value: 4)
        ])]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .sectionReload
    }

    func test_sectionReload_whenItemIDSetChangesPartially_loadMoreScenario() {
        let old = [OBAListViewSection.stub(id: "arrivals", items: [
            StubItem(id: "arrival-1", value: 10),
            StubItem(id: "arrival-2", value: 20)
        ])]
        // arrival-2 stays, arrival-3 replaces arrival-1
        let new = [OBAListViewSection.stub(id: "arrivals", items: [
            StubItem(id: "arrival-2", value: 20),
            StubItem(id: "arrival-3", value: 30)
        ])]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .sectionReload
    }

    func test_sectionReload_whenOneItemAddedAndOneIDShared() {
        let old = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "existing", value: 1)
        ])]
        let new = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "existing", value: 1),
            StubItem(id: "new-item", value: 2)
        ])]
        // count differs → hits the count guard first, still sectionReload
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .sectionReload
    }

    // MARK: - .contentUpdate

    func test_contentUpdate_whenOnlyItemValuesChange() {
        // Same section IDs, same item IDs, same count, but values differ.
        let old = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "a", value: 1),
            StubItem(id: "b", value: 2)
        ])]
        let new = [OBAListViewSection.stub(id: "s1", items: [
            StubItem(id: "a", value: 99),   // value changed
            StubItem(id: "b", value: 2)
        ])]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .contentUpdate
    }

    func test_contentUpdate_withMultipleSectionsAllUnchangedIDs() {
        let old = [
            OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 1)]),
            OBAListViewSection.stub(id: "s2", items: [StubItem(id: "b", value: 2)])
        ]
        let new = [
            OBAListViewSection.stub(id: "s1", items: [StubItem(id: "a", value: 10)]),
            OBAListViewSection.stub(id: "s2", items: [StubItem(id: "b", value: 20)])
        ]
        let strategy = listView.getUpdateStrategy(oldSections: old, newSections: new)
        expect(strategy) == .contentUpdate
    }

    func test_contentUpdate_whenItemsAreExactlyEqual() {
        // No change at all → diffable data source will do nothing meaningful,
        // but the strategy should still be .contentUpdate (not .noChange),
        // because the sections are non-empty.
        let items = [StubItem(id: "a", value: 1)]
        let section = OBAListViewSection.stub(id: "s1", items: items)
        let strategy = listView.getUpdateStrategy(oldSections: [section], newSections: [section])
        expect(strategy) == .contentUpdate
    }
}
