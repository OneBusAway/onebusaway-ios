//
//  AgencyAlertsViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SafariServices
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class AgencyAlertsViewControllerTests: OBATestCase {

    var queue: OperationQueue!
    var app: Application!

    private struct MockAlert: TransitAlertViewModel, Hashable {
        let titleText: String?
        let bodyText: String?
        let urlValue: URL?

        func title(forLocale locale: Locale) -> String? { titleText }
        func body(forLocale locale: Locale) -> String? { bodyText }
        func url(forLocale locale: Locale) -> URL? { urlValue }
    }

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let dataLoader = MockDataLoader(testName: name)
        app = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Tests

    @Test func testInitializationAndDefaultProperties() {
        let controller = AgencyAlertsViewController(application: app)

        let expectedTitle = OBALoc("agency_alerts_controller.title", value: "Alerts", comment: "The title of the Agency Alerts controller.")
        #expect(controller.title == expectedTitle)
        #expect(controller.listView.obaDataSource === controller)
        #expect(controller.listView.collapsibleSectionsDelegate === controller)
        #expect(controller.listView.contextMenuDelegate === controller)
        #expect(controller.collapsedSections.isEmpty)
    }

    @Test func testEmptyDataProvidesStandardViewModelWithRegionName() {
        let controller = AgencyAlertsViewController(application: app)
        let emptyData = controller.emptyData(for: controller.listView)

        guard case .standard(let viewModel) = emptyData else {
            Issue.record("Expected standard empty data view model")
            return
        }

        #expect(viewModel.title == Strings.emptyAlertTitle)
        #expect(viewModel.body == Fixtures.pugetSoundRegion.name)
    }

    @Test func testPreviewAlertReturnsSafariViewControllerForURL() {
        let controller = AgencyAlertsViewController(application: app)
        let alertWithURL = MockAlert(
            titleText: "Alert with Link",
            bodyText: "Body",
            urlValue: URL(string: "https://example.com/alerts/1")
        )
        let item = TransitAlertDataListViewModel(alertWithURL, forLocale: Locale(identifier: "en"))

        let previewController = controller.previewAlert(item)

        #expect(previewController is SFSafariViewController)
        #expect(controller.previewingVC?.identifier == item.id)
        #expect(controller.previewingVC?.vc === previewController)
    }

    @Test func testPreviewAlertReturnsTransitAlertDetailViewControllerWhenNoURL() {
        let controller = AgencyAlertsViewController(application: app)
        let alertWithoutURL = MockAlert(
            titleText: "Alert without Link",
            bodyText: "Body only",
            urlValue: nil
        )
        let item = TransitAlertDataListViewModel(alertWithoutURL, forLocale: Locale(identifier: "en"))

        let previewController = controller.previewAlert(item)

        #expect(previewController is TransitAlertDetailViewController)
        #expect(controller.previewingVC?.identifier == item.id)
        #expect(controller.previewingVC?.vc === previewController)
    }

    @Test func testContextMenuConfigurationForAlertItem() {
        let controller = AgencyAlertsViewController(application: app)
        let alert = MockAlert(
            titleText: "Detour",
            bodyText: "Detour description",
            urlValue: URL(string: "https://example.com/detour")
        )
        let item = TransitAlertDataListViewModel(alert, forLocale: Locale(identifier: "en"))

        let menuActions = controller.contextMenu(controller.listView, for: item.typeErased)

        #expect(menuActions != nil)
        let resolvedPreview = menuActions?.previewProvider?()
        #expect(resolvedPreview is SFSafariViewController)

        let menu = menuActions?.contextMenuProvider?([])
        #expect(menu?.children.count == 1)
        let shareAction = menu?.children.first as? UIAction
        #expect(shareAction?.title == Strings.share)
        #expect(shareAction?.image == Icons.share)
    }

    @Test func testContextMenuConfigurationReturnsNilForUnrecognizedItem() {
        let controller = AgencyAlertsViewController(application: app)
        let unrecognizedItem = OBAListRowView.DefaultViewModel(title: "Generic Item").typeErased

        let menuActions = controller.contextMenu(controller.listView, for: unrecognizedItem)
        #expect(menuActions == nil)
    }
}
