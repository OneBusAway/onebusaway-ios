//
//  OBAListViewSectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// `NSDiffableDataSource` uses `Hashable` as identity. `hash(into:)` already
/// combines `id`; `==` used not to — undefined behavior under the Hashable
/// contract (#421 / #1327).
///
/// #1338: a causal link from that mismatch to the historical
/// "Failed to find index of item OBAListViewHeader" spam is unproven; these
/// tests only lock the contract.
@Suite(.serialized)
struct OBAListViewSectionTests {

    private func section(id: String, title: String?) -> OBAListViewSection {
        OBAListViewSection(id: id, title: title, contents: [OBAListRowView.DefaultViewModel]())
    }

    @Test func `Sections with the same title and contents but different ids are not equal`() {
        let ferriesA = section(id: "agency_alerts_Washington State Ferries", title: "Washington State Ferries")
        let ferriesB = section(id: "agency_alerts_Washington State Ferries (other)", title: "Washington State Ferries")

        #expect(ferriesA != ferriesB)
    }

    @Test func `Equal sections include id and have matching hashes`() {
        let a = section(id: "agency_alerts_Washington State Ferries", title: "Washington State Ferries")
        let b = section(id: "agency_alerts_Washington State Ferries", title: "Washington State Ferries")

        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func `Section header visibility depends on title`() {
        let withTitle = OBAListViewSection(id: "sec_1", title: "Arrivals", contents: [OBAListRowView.DefaultViewModel]())
        #expect(withTitle.hasHeader == true)

        let withEmptyTitle = OBAListViewSection(id: "sec_2", title: "", contents: [OBAListRowView.DefaultViewModel]())
        #expect(withEmptyTitle.hasHeader == true)

        let withoutTitle = OBAListViewSection(id: "sec_3", title: nil, contents: [OBAListRowView.DefaultViewModel]())
        #expect(withoutTitle.hasHeader == false)
    }

    @Test func `Default list configuration is insetGrouped`() {
        let sec = OBAListViewSection(id: "sec_config", title: "Test", contents: [OBAListRowView.DefaultViewModel]())
        #expect(sec.configuration.appearance == .insetGrouped)
        #expect(sec.configuration.backgroundColor == nil)

        var mutableSec = sec
        mutableSec.configuration = .init(appearance: .plain, backgroundColor: .red)
        #expect(mutableSec.configuration.appearance == .plain)
        #expect(mutableSec.configuration.backgroundColor == .red)
    }

    @Test func `CollapseState does not affect equality`() {
        var secA = OBAListViewSection(id: "sec_collapse", title: "Collapsible", contents: [OBAListRowView.DefaultViewModel]())
        var secB = OBAListViewSection(id: "sec_collapse", title: "Collapsible", contents: [OBAListRowView.DefaultViewModel]())

        secA.collapseState = .collapsed
        secB.collapseState = .expanded

        // Per implementation, collapseState is omitted from == to avoid confusing UICollectionView animations
        #expect(secA == secB)
        #expect(secA.hashValue == secB.hashValue)
    }

    @Test func `Subscript safely accesses items and handles out-of-bounds`() {
        let item1 = OBAListRowView.DefaultViewModel(title: "Item 1")
        let item2 = OBAListRowView.DefaultViewModel(title: "Item 2")
        let sectionWithItems = OBAListViewSection(id: "sec_items", title: "Items", contents: [item1, item2])

        #expect(sectionWithItems.contents.count == 2)
        #expect(sectionWithItems[0] == AnyOBAListViewItem(item1))
        #expect(sectionWithItems[1] == AnyOBAListViewItem(item2))
        #expect(sectionWithItems[-1] == nil)
        #expect(sectionWithItems[2] == nil)
        #expect(sectionWithItems[100] == nil)
    }

    @Test func `Init does not re-wrap already type-erased contents`() {
        let rawItem = OBAListRowView.DefaultViewModel(title: "Raw Item")
        let typeErasedItem = AnyOBAListViewItem(rawItem)

        let section = OBAListViewSection(id: "sec_erased", title: "Erased", contents: [typeErasedItem])
        #expect(section.contents.count == 1)
        #expect(section.contents[0] == typeErasedItem)
    }
}
