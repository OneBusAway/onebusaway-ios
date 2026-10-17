//
//  OBAListViewItemTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// MARK: - Test Helpers

nonisolated private struct MockListItem: OBAListViewItem {
    let id: String
    var title: String
    var onSelectAction: OBAListViewAction<MockListItem>?
    var onDeleteAction: OBAListViewAction<MockListItem>?
    var leadingContextualActions: [OBAListViewContextualAction<MockListItem>]?
    var trailingContextualActions: [OBAListViewContextualAction<MockListItem>]?
    var separatorConfiguration: OBAListRowSeparatorConfiguration = .init()

    var configuration: OBAListViewItemConfiguration {
        var config = UIListContentConfiguration.cell()
        config.text = title
        return .list(config, [])
    }

    /// Hashes the mock item by its ID and title.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
    }

    /// Compares two mock list items for equality by ID and title.
    static func == (lhs: MockListItem, rhs: MockListItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}

nonisolated private struct CustomCellMockItem: OBAListViewItem {
    let id: String

    var configuration: OBAListViewItemConfiguration {
        .custom(MockContentConfiguration())
    }

    static var customCellType: OBAListViewCell.Type? {
        MockListViewCell.self
    }

    /// Hashes the custom cell mock item by its ID.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Compares two custom cell mock items for equality by ID.
    static func == (lhs: CustomCellMockItem, rhs: CustomCellMockItem) -> Bool {
        lhs.id == rhs.id
    }
}

private final class MockListViewCell: OBAListViewCell {}

nonisolated private struct MockContentConfiguration: OBAContentConfiguration {
    var formatters: Formatters?
    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        MockListViewCell.self
    }
}

// MARK: - Suite

@MainActor
@Suite(.serialized)
struct OBAListViewItemTests {

    // MARK: - Default Protocol Implementations

    /// Tests protocol default values for OBAListViewItem conformance.
    @Test func testProtocolDefaultImplementations() {
        nonisolated struct DefaultItem: OBAListViewItem {
            let id: String = "default"
            var configuration: OBAListViewItemConfiguration {
                .list(UIListContentConfiguration.cell(), [])
            }
        }

        let item = DefaultItem()
        #expect(DefaultItem.customCellType == nil)
        #expect(item.separatorConfiguration == OBAListRowSeparatorConfiguration())
        #expect(item.onSelectAction == nil)
        #expect(item.onDeleteAction == nil)
        #expect(item.leadingContextualActions == nil)
        #expect(item.trailingContextualActions == nil)
        #expect(item.typeErased.id == AnyHashable("default"))
    }

    // MARK: - AnyOBAListViewItem Identity & Type Erasure

    /// Tests type erasure and property propagation into AnyOBAListViewItem.
    @Test func testTypeErasureProperties() {
        let separator = OBAListRowSeparatorConfiguration.hidden()
        let item = MockListItem(
            id: "item_1",
            title: "Item One",
            separatorConfiguration: separator
        )

        let anyItem = AnyOBAListViewItem(item)
        #expect(anyItem.id == AnyHashable("item_1"))
        #expect(anyItem.separatorConfiguration == separator)

        if case .list(let listConfig, let accessories) = anyItem.configuration {
            #expect(listConfig.text == "Item One")
            #expect(accessories.isEmpty)
        } else {
            Issue.record("Expected .list configuration")
        }
    }

    /// Tests downcasting AnyOBAListViewItem back to its underlying concrete type.
    @Test func testTypeCasting() {
        let item = MockListItem(id: "item_cast", title: "Casting Test")
        let anyItem = item.typeErased

        let casted = anyItem.as(MockListItem.self)
        #expect(casted != nil)
        #expect(casted?.id == "item_cast")
        #expect(casted?.title == "Casting Test")

        let wrongCast = anyItem.as(OBAListViewHeader.self)
        #expect(wrongCast == nil)
    }

    /// Tests AnyOBAListViewItem wrapping an item with a custom cell type.
    @Test func testCustomCellTypeItem() {
        let customItem = CustomCellMockItem(id: "custom_cell_item")
        #expect(CustomCellMockItem.customCellType == MockListViewCell.self)

        let anyItem = customItem.typeErased
        #expect(anyItem.id == AnyHashable("custom_cell_item"))
        if case .custom = anyItem.configuration {
            // Expected custom configuration
        } else {
            Issue.record("Expected .custom configuration")
        }
    }

    // MARK: - AnyOBAListViewItem Equality & Hashing

    /// Tests AnyOBAListViewItem equality, hash consistency, and Set uniqueness.
    @Test func testEqualityAndHashing() {
        let itemA1 = MockListItem(id: "item_1", title: "Title A")
        let itemA2 = MockListItem(id: "item_1", title: "Title A")
        let itemB = MockListItem(id: "item_1", title: "Title B")
        let itemC = MockListItem(id: "item_2", title: "Title A")

        let anyA1 = AnyOBAListViewItem(itemA1)
        let anyA2 = AnyOBAListViewItem(itemA2)
        let anyB = AnyOBAListViewItem(itemB)
        let anyC = AnyOBAListViewItem(itemC)

        #expect(anyA1 == anyA2)
        #expect(anyA1.hashValue == anyA2.hashValue)

        #expect(anyA1 != anyB)
        #expect(anyA1 != anyC)

        let set: Set<AnyOBAListViewItem> = [anyA1, anyA2, anyB]
        #expect(set.count == 2)
        #expect(set.contains(anyA1))
        #expect(set.contains(anyB))
        #expect(!set.contains(anyC))
    }

    /// Tests inequality between different item types sharing the same ID.
    @Test func testInequalityAcrossDifferentTypesWithSameID() {
        let mockItem = MockListItem(id: "same_id", title: "Same ID")
        let headerItem = OBAListViewHeader(id: "same_id", title: "Same ID", isCollapsible: false)

        let anyMock = AnyOBAListViewItem(mockItem)
        let anyHeader = AnyOBAListViewItem(headerItem)

        #expect(anyMock != anyHeader)
    }

    // MARK: - Action Type Erasure & Execution

    /// Tests type-erased onSelectAction execution and item forwarding.
    @Test func testOnSelectActionExecution() {
        var selectedItemTitle: String?
        let onSelect: OBAListViewAction<MockListItem> = { item in
            selectedItemTitle = item.title
        }

        let item = MockListItem(id: "select_test", title: "Selected Title", onSelectAction: onSelect)
        let anyItem = AnyOBAListViewItem(item)

        let erasedAction = anyItem.onSelectAction
        #expect(erasedAction != nil)

        erasedAction?(anyItem)
        #expect(selectedItemTitle == "Selected Title")
    }

    /// Tests type-erased onDeleteAction execution and item forwarding.
    @Test func testOnDeleteActionExecution() {
        var deletedItemID: String?
        let onDelete: OBAListViewAction<MockListItem> = { item in
            deletedItemID = item.id
        }

        let item = MockListItem(id: "delete_test", title: "Delete Title", onDeleteAction: onDelete)
        let anyItem = AnyOBAListViewItem(item)

        let erasedDelete = anyItem.onDeleteAction
        #expect(erasedDelete != nil)

        erasedDelete?(anyItem)
        #expect(deletedItemID == "delete_test")
    }

    /// Tests that unconfigured action closures remain nil on AnyOBAListViewItem.
    @Test func testNilActionsWhenUnset() {
        let item = MockListItem(id: "nil_actions", title: "No Actions")
        let anyItem = AnyOBAListViewItem(item)

        #expect(anyItem.onSelectAction == nil)
        #expect(anyItem.onDeleteAction == nil)
        #expect(anyItem.leadingContextualActions == nil)
        #expect(anyItem.trailingContextualActions == nil)
    }

    // MARK: - Contextual Actions

    /// Tests default properties and custom configurations of OBAListViewContextualAction.
    @Test func testContextualActionDefaultsAndCustomization() {
        let defaultAction = OBAListViewContextualAction<MockListItem>()
        #expect(defaultAction.style == .normal)
        #expect(defaultAction.title == nil)
        #expect(defaultAction.image == nil)
        #expect(defaultAction.textColor == ThemeColors.shared.lightText)
        #expect(defaultAction.backgroundColor == ThemeColors.shared.blue)
        #expect(defaultAction.hidesWhenSelected == false)

        let image = UIImage(systemName: "star")
        var customAction = OBAListViewContextualAction<MockListItem>(
            style: .destructive,
            title: "Favorite",
            image: image,
            backgroundColor: .systemYellow,
            hidesWhenSelected: true
        )
        customAction.textColor = .white

        #expect(customAction.style == .destructive)
        #expect(customAction.title == "Favorite")
        #expect(customAction.image == image)
        #expect(customAction.backgroundColor == .systemYellow)
        #expect(customAction.textColor == .white)
        #expect(customAction.hidesWhenSelected == true)
    }

    /// Tests bridging an OBAListViewContextualAction to a UIKit UIContextualAction and executing its handler.
    @Test func testUIContextualActionBridge() {
        var handlerInvoked = false
        var invokedItemTitle: String?

        let item = MockListItem(id: "ctx_1", title: "Action Item")
        let action = OBAListViewContextualAction<MockListItem>(
            style: .destructive,
            title: "Remove",
            image: UIImage(systemName: "trash"),
            backgroundColor: .red,
            hidesWhenSelected: true,
            item: item,
            handler: { receivedItem in
                handlerInvoked = true
                invokedItemTitle = receivedItem.title
            }
        )

        let uiAction = action.contextualAction
        #expect(uiAction.style == .destructive)
        #expect(uiAction.title == "Remove")
        #expect(uiAction.image == UIImage(systemName: "trash"))
        #expect(uiAction.backgroundColor == .red)

        var completionSuccess: Bool?
        uiAction.handler(uiAction, UIView()) { success in
            completionSuccess = success
        }
        #expect(handlerInvoked)
        #expect(invokedItemTitle == "Action Item")
        #expect(completionSuccess == true)
    }

    /// Tests type erasure of contextual actions and invocation on AnyOBAListViewItem.
    @Test func testContextualActionsTypeErasureAndInvocation() {
        var triggeredActionTitle: String?
        let contextualAction = OBAListViewContextualAction<MockListItem>(
            style: .normal,
            title: "Pin",
            image: UIImage(systemName: "pin"),
            textColor: .yellow,
            backgroundColor: .purple,
            hidesWhenSelected: true,
            item: nil,
            handler: { item in
                triggeredActionTitle = item.title
            }
        )

        let item = MockListItem(
            id: "lead_test",
            title: "Leading Test",
            leadingContextualActions: [contextualAction]
        )

        let anyItem = AnyOBAListViewItem(item)
        let erasedActions = anyItem.leadingContextualActions
        #expect(erasedActions?.count == 1)

        guard let firstErased = erasedActions?.first else {
            Issue.record("Expected erased action")
            return
        }

        #expect(firstErased.title == "Pin")
        #expect(firstErased.style == .normal)
        #expect(firstErased.image == UIImage(systemName: "pin"))
        #expect(firstErased.textColor == .yellow)
        #expect(firstErased.backgroundColor == .purple)
        #expect(firstErased.hidesWhenSelected == true)

        firstErased.handler?(anyItem)
        #expect(triggeredActionTitle == "Leading Test")
    }

    // MARK: - OBAListViewHeader

    /// Tests configuration generation for collapsible and static section headers.
    @Test func testListViewHeaderConfiguration() {
        let collapsibleHeader = OBAListViewHeader(id: "sec_1", title: "Departures", isCollapsible: true)
        #expect(collapsibleHeader.id == "sec_1")
        #expect(collapsibleHeader.title == "Departures")
        #expect(collapsibleHeader.isCollapsible == true)

        if case .list(let config, let accessories) = collapsibleHeader.configuration {
            #expect(config.text == "Departures")
            #expect(accessories.count == 1)
            #expect(accessories.first != nil)
        } else {
            Issue.record("Expected .list configuration on header")
        }

        let nonCollapsibleHeader = OBAListViewHeader(id: "sec_2", title: "Static Header", isCollapsible: false)
        #expect(nonCollapsibleHeader.isCollapsible == false)

        if case .list(let config, let accessories) = nonCollapsibleHeader.configuration {
            #expect(config.text == "Static Header")
            #expect(accessories.count == 1)
            #expect(accessories.first != nil)
        } else {
            Issue.record("Expected .list configuration on header")
        }
    }

    /// Tests equality and hash consistency of OBAListViewHeader across varying IDs, titles, and collapse states.
    @Test func testListViewHeaderEqualityAndHashing() {
        let h1 = OBAListViewHeader(id: "h_1", title: "Header", isCollapsible: true)
        let h2 = OBAListViewHeader(id: "h_1", title: "Header", isCollapsible: true)
        let hDiffID = OBAListViewHeader(id: "h_2", title: "Header", isCollapsible: true)
        let hDiffTitle = OBAListViewHeader(id: "h_1", title: "Other", isCollapsible: true)
        let hDiffCollapsible = OBAListViewHeader(id: "h_1", title: "Header", isCollapsible: false)

        #expect(h1 == h2)
        #expect(h1.hashValue == h2.hashValue)

        #expect(h1 != hDiffID)
        #expect(h1 != hDiffTitle)
        #expect(h1 != hDiffCollapsible)
    }

    // MARK: - EmptyDataSetItem (Production OBAListViewItem)

    /// Tests custom cell type and content configuration for EmptyDataSetItem.
    @Test func testEmptyDataSetItemConfigurationAndCustomCellType() {
        let item = EmptyDataSetItem(id: "empty_1", title: "No Data", body: "Try again later")
        #expect(EmptyDataSetItem.customCellType == EmptyDataSetCell.self)
        #expect(item.id == "empty_1")
        #expect(item.title == "No Data")
        #expect(item.body == "Try again later")
        #expect(item.alignment == .top)

        if case .custom(let config) = item.configuration {
            #expect(ObjectIdentifier(config.obaContentView) == ObjectIdentifier(EmptyDataSetCell.self))
        } else {
            Issue.record("Expected .custom configuration for EmptyDataSetItem")
        }
    }

    /// Tests that EmptyDataSetItem maps various APIError cases to their appropriate SF Symbols.
    @Test func testEmptyDataSetItemErrorMappingIcons() {
        let networkErrorItem = EmptyDataSetItem(
            id: "net_err",
            error: APIError.networkFailure(URLError(.notConnectedToInternet))
        )
        #expect(networkErrorItem.alignment == .center)
        #expect(networkErrorItem.image == UIImage(systemName: "wifi.slash"))

        let serverErrorItem = EmptyDataSetItem(
            id: "srv_err",
            error: APIError.serverError(regionName: "Test")
        )
        #expect(serverErrorItem.image == UIImage(systemName: "server.rack"))

        let cellularErrorItem = EmptyDataSetItem(id: "cell_err", error: APIError.cellularDataRestricted)
        #expect(cellularErrorItem.image == UIImage(systemName: "wifi.slash"))

        let noRegionItem = EmptyDataSetItem(id: "reg_err", error: APIError.noRegionSelected)
        #expect(noRegionItem.image == UIImage(systemName: "location.slash"))

        let url = URL(string: "https://api.pugetsound.onebusaway.org/api/where/stop/1_75403.json")!
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let notFoundItem = EmptyDataSetItem(id: "not_found", error: APIError.requestNotFound(response))
        #expect(notFoundItem.image == UIImage(systemName: "questionmark.square.dashed"))

        let customIcon = UIImage(systemName: "star")
        let explicitIconItem = EmptyDataSetItem(
            id: "exp_err",
            error: APIError.serverError(regionName: "Test"),
            image: customIcon
        )
        #expect(explicitIconItem.image == customIcon)
    }

    /// Tests equality, hashing, and ID discrimination for EmptyDataSetItem.
    @Test func testEmptyDataSetItemEqualityAndHashing() {
        let item1 = EmptyDataSetItem(id: "e1", title: "Title", body: "Body")
        let item2 = EmptyDataSetItem(id: "e1", title: "Title", body: "Body")
        let itemDiffID = EmptyDataSetItem(id: "e2", title: "Title", body: "Body")
        let itemDiffTitle = EmptyDataSetItem(id: "e1", title: "Different", body: "Body")

        #expect(item1 == item2)
        #expect(item1.hashValue == item2.hashValue)
        #expect(item1 != itemDiffID)
        #expect(item1 != itemDiffTitle)
    }
}

