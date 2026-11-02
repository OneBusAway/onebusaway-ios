//
//  TransitAlertViewModelTests.swift
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

@MainActor
@Suite(.serialized)
final class TransitAlertViewModelTests {

    private struct MockAlert: TransitAlertViewModel, Hashable {
        let titleText: String?
        let bodyText: String?
        let urlValue: URL?

        func title(forLocale locale: Locale) -> String? { titleText }
        func body(forLocale locale: Locale) -> String? { bodyText }
        func url(forLocale locale: Locale) -> URL? { urlValue }
    }

    // MARK: - TransitAlertDataListViewModel Properties & Truncation

    @Test func testInitializationAndSubtitleTruncation() {
        let shortAlert = MockAlert(
            titleText: "Construction Detour",
            bodyText: "Buses are detoured on 3rd Ave.",
            urlValue: URL(string: "https://example.com/detour")
        )

        let shortVM = TransitAlertDataListViewModel(
            shortAlert,
            isUnread: true,
            forLocale: Locale(identifier: "en")
        )

        #expect(shortVM.title == "Construction Detour")
        #expect(shortVM.body == "Buses are detoured on 3rd Ave.")
        #expect(shortVM.subtitle == "Buses are detoured on 3rd Ave.")
        #expect(shortVM.localizedURL == URL(string: "https://example.com/detour"))
        #expect(shortVM.isUnread == true)

        let longText = String(repeating: "A", count: 300)
        let longAlert = MockAlert(titleText: "Long Notice", bodyText: longText, urlValue: nil)
        let longVM = TransitAlertDataListViewModel(longAlert, forLocale: Locale(identifier: "en"))

        #expect(longVM.body.count == 300)
        #expect(longVM.subtitle.count == 256)
        #expect(longVM.subtitle == String(repeating: "A", count: 256))
    }

    @Test func testNilTitleAndBodyFallbackToEmptyString() {
        let emptyAlert = MockAlert(titleText: nil, bodyText: nil, urlValue: nil)
        let vm = TransitAlertDataListViewModel(emptyAlert, forLocale: Locale(identifier: "en"))

        #expect(vm.title == "")
        #expect(vm.body == "")
        #expect(vm.subtitle == "")
        #expect(vm.localizedURL == nil)
    }

    // MARK: - Row Configuration & Unread Icons

    @Test func testUnreadAlertRowConfiguration() {
        let alert = MockAlert(titleText: "Alert Title", bodyText: "Alert Body", urlValue: nil)
        let unreadVM = TransitAlertDataListViewModel(alert, isUnread: true, forLocale: Locale(identifier: "en"))

        guard case .custom(let obaConfig) = unreadVM.configuration,
              let rowConfig = obaConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom configuration")
            return
        }

        #expect(rowConfig.text == .string("Alert Title"))
        #expect(rowConfig.secondaryText == .string("Alert Body"))
        #expect(rowConfig.appearance == .subtitle)
        #expect(rowConfig.accessoryType == .disclosureIndicator)
        #expect(rowConfig.textConfig.numberOfLines == 2)
        #expect(rowConfig.secondaryTextConfig.numberOfLines == 3)
        #expect(rowConfig.textConfig.accessibilityNumberOfLines == 5)
        #expect(rowConfig.secondaryTextConfig.accessibilityNumberOfLines == 8)

        let expectedUnreadImage = Icons.unreadAlert.applyingSymbolConfiguration(.init(textStyle: .body))
        #expect(rowConfig.image == expectedUnreadImage)
    }

    @Test func testReadAlertRowConfiguration() {
        let alert = MockAlert(titleText: "Alert Title", bodyText: "Alert Body", urlValue: nil)
        let readVM = TransitAlertDataListViewModel(alert, isUnread: false, forLocale: Locale(identifier: "en"))

        guard case .custom(let obaConfig) = readVM.configuration,
              let rowConfig = obaConfig as? OBAListRowConfiguration else {
            Issue.record("Expected OBAListRowConfiguration inside .custom configuration")
            return
        }

        let expectedReadImage = Icons.readAlert.applyingSymbolConfiguration(.init(textStyle: .body))
        #expect(rowConfig.image == expectedReadImage)
    }

    // MARK: - Model Identity

    @Test func testEqualityAndHashingDistinguishesInstances() {
        let alert = MockAlert(titleText: "Alert", bodyText: "Body", urlValue: nil)
        let vm1 = TransitAlertDataListViewModel(alert, forLocale: Locale(identifier: "en"))
        let vm2 = TransitAlertDataListViewModel(alert, forLocale: Locale(identifier: "en"))

        // Distinct instances have distinct UUID identifiers
        #expect(vm1.id != vm2.id)
        #expect(vm1 != vm2)
    }
}
