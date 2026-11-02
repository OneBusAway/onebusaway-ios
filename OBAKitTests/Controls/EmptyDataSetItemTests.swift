//
//  EmptyDataSetItemTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class EmptyDataSetItemTests {

    private var dummyResponse: HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    @Test func testInitWithExplicitProperties() {
        let item = EmptyDataSetItem(
            id: "custom_empty",
            alignment: .bottom,
            title: "No Data",
            body: "Please try again later.",
            image: UIImage(systemName: "tray"),
            buttonConfig: nil
        )

        #expect(item.id == "custom_empty")
        #expect(item.alignment == .bottom)
        #expect(item.title == "No Data")
        #expect(item.body == "Please try again later.")
        #expect(item.image == UIImage(systemName: "tray"))
        #expect(EmptyDataSetItem.customCellType == EmptyDataSetCell.self)

        guard case let .custom(config) = item.configuration else {
            Issue.record("Expected .custom configuration")
            return
        }
        #expect(config.obaContentView == EmptyDataSetCell.self)
    }

    @Test func testInitWithErrorMapsAPIErrorsToCorrectIcons() {
        let networkError = APIError.networkFailure(URLError(.notConnectedToInternet))
        let networkItem = EmptyDataSetItem(id: "network_err", error: networkError)
        #expect(networkItem.alignment == .center)
        #expect(networkItem.title == nil)
        #expect(networkItem.body == networkError.localizedDescription)
        #expect(networkItem.image == UIImage(systemName: "wifi.slash"))

        let serverError = APIError.serverError(regionName: "Puget Sound")
        let serverItem = EmptyDataSetItem(id: "server_err", error: serverError)
        #expect(serverItem.image == UIImage(systemName: "server.rack"))

        let notFoundError = APIError.requestNotFound(dummyResponse)
        let notFoundItem = EmptyDataSetItem(id: "not_found", error: notFoundError)
        #expect(notFoundItem.image == UIImage(systemName: "questionmark.square.dashed"))

        let noRegionError = APIError.noRegionSelected
        let noRegionItem = EmptyDataSetItem(id: "no_region", error: noRegionError)
        #expect(noRegionItem.image == UIImage(systemName: "location.slash"))
    }

    @Test func testInitWithErrorRespectsExplicitImageOverride() {
        let overrideImage = UIImage(systemName: "star.fill")
        let error = APIError.serverError(regionName: "Puget Sound")
        let item = EmptyDataSetItem(id: "override_img", error: error, image: overrideImage)

        #expect(item.image == overrideImage)
    }

    @Test func testEqualityAndHashingDistinguishDifferentIDsAndAlignments() {
        let item1 = EmptyDataSetItem(id: "id_1", alignment: .top, title: "Title", body: "Body")
        let item2 = EmptyDataSetItem(id: "id_2", alignment: .top, title: "Title", body: "Body")
        let item3 = EmptyDataSetItem(id: "id_1", alignment: .center, title: "Title", body: "Body")

        #expect(item1 != item2)
        #expect(item1 != item3)

        var hasher1 = Hasher()
        item1.hash(into: &hasher1)

        var hasher2 = Hasher()
        item2.hash(into: &hasher2)

        #expect(hasher1.finalize() != hasher2.finalize())
    }

    @Test func testEmptyDataSetCellAppliesConfiguration() {
        let cell = EmptyDataSetCell(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let item = EmptyDataSetItem(
            id: "apply_test",
            alignment: .top,
            title: "Header Title",
            body: "Explanation text",
            image: UIImage(systemName: "bell")
        )
        let config = EmptyDataSetContentConfiguration(viewModel: item)

        cell.apply(config)

        #expect(cell.emptyDataView.titleLabel.text == "Header Title")
        #expect(cell.emptyDataView.bodyLabel.text == "Explanation text")
        #expect(cell.emptyDataView.imageView.image == UIImage(systemName: "bell"))
        #expect(cell.emptyDataView.alignment == .top)
    }
}
