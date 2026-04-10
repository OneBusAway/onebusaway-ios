//
//  MoreTabConfigurationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

class MoreTabConfigurationTests: XCTestCase {

    // MARK: - Default Configuration

    func test_defaultConfiguration_hasExpectedValues() {
        let config = MoreTabConfiguration.default
        XCTAssertNil(config.headerSupportText)
        XCTAssertTrue(config.showHelpOutSection)
        XCTAssertEqual(
            config.translateURL?.absoluteString,
            "https://www.transifex.com/open-transit-software-foundation/onebusaway-ios/"
        )
        XCTAssertEqual(
            config.developURL?.absoluteString,
            "https://github.com/oneBusAway/onebusaway-ios"
        )
        XCTAssertTrue(config.customLinks.isEmpty)
    }

    // MARK: - Parsing from Dictionary

    func test_parseFromDictionary_withAllFields() {
        let dict: [AnyHashable: Any] = [
            "HeaderSupportText": "Powered by TestAgency",
            "ShowHelpOutSection": false,
            "TranslateURL": "https://example.com/translate",
            "DevelopURL": "https://example.com/develop",
            "CustomLinks": [
                ["Title": "Agency Site", "URL": "https://example.com"],
                ["Title": "Call Us", "URL": "tel:+1234567890"]
            ]
        ]

        let config = MoreTabConfiguration(from: dict)

        XCTAssertEqual(config.headerSupportText, "Powered by TestAgency")
        XCTAssertFalse(config.showHelpOutSection)
        XCTAssertEqual(config.translateURL?.absoluteString, "https://example.com/translate")
        XCTAssertEqual(config.developURL?.absoluteString, "https://example.com/develop")
        XCTAssertEqual(config.customLinks.count, 2)
        XCTAssertEqual(config.customLinks[0].title, "Agency Site")
        XCTAssertEqual(config.customLinks[0].url.absoluteString, "https://example.com")
        XCTAssertEqual(config.customLinks[1].title, "Call Us")
        XCTAssertEqual(config.customLinks[1].url.absoluteString, "tel:+1234567890")
    }

    func test_parseFromDictionary_withMinimalFields() {
        let dict: [AnyHashable: Any] = [:]
        let config = MoreTabConfiguration(from: dict)

        XCTAssertNil(config.headerSupportText)
        XCTAssertTrue(config.showHelpOutSection)
        XCTAssertEqual(
            config.translateURL?.absoluteString,
            "https://www.transifex.com/open-transit-software-foundation/onebusaway-ios/"
        )
        XCTAssertEqual(
            config.developURL?.absoluteString,
            "https://github.com/oneBusAway/onebusaway-ios"
        )
        XCTAssertTrue(config.customLinks.isEmpty)
    }

    func test_parseFromDictionary_withPartialFields() {
        let dict: [AnyHashable: Any] = [
            "ShowHelpOutSection": false,
            "TranslateURL": "https://custom-translate.com"
        ]
        let config = MoreTabConfiguration(from: dict)

        XCTAssertNil(config.headerSupportText)
        XCTAssertFalse(config.showHelpOutSection)
        XCTAssertEqual(config.translateURL?.absoluteString, "https://custom-translate.com")
        XCTAssertEqual(
            config.developURL?.absoluteString,
            "https://github.com/oneBusAway/onebusaway-ios"
        )
        XCTAssertTrue(config.customLinks.isEmpty)
    }

    // MARK: - MoreTabLinkItem

    func test_linkItem_validDictionary_succeeds() {
        let dict: [AnyHashable: Any] = [
            "Title": "Test Link",
            "URL": "https://example.com"
        ]
        let item = MoreTabLinkItem(dictionary: dict)

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Test Link")
        XCTAssertEqual(item?.url.absoluteString, "https://example.com")
    }

    func test_linkItem_missingTitle_returnsNil() {
        let dict: [AnyHashable: Any] = ["URL": "https://example.com"]
        XCTAssertNil(MoreTabLinkItem(dictionary: dict))
    }

    func test_linkItem_missingURL_returnsNil() {
        let dict: [AnyHashable: Any] = ["Title": "Test"]
        XCTAssertNil(MoreTabLinkItem(dictionary: dict))
    }

    func test_linkItem_emptyURL_returnsNil() {
        let dict: [AnyHashable: Any] = ["Title": "Test", "URL": ""]
        XCTAssertNil(MoreTabLinkItem(dictionary: dict))
    }

    func test_linkItem_malformedLinksFiltered_inConfiguration() {
        let dict: [AnyHashable: Any] = [
            "CustomLinks": [
                ["Title": "Valid", "URL": "https://example.com"],
                ["Title": "Missing URL"],
                ["URL": "https://no-title.com"],
                ["Title": "Empty URL", "URL": ""]
            ]
        ]
        let config = MoreTabConfiguration(from: dict)
        XCTAssertEqual(config.customLinks.count, 1)
        XCTAssertEqual(config.customLinks[0].title, "Valid")
        XCTAssertEqual(config.customLinks[0].url.absoluteString, "https://example.com")
    }

    // MARK: - Direct Initializer

    func test_directInitializer_setsAllProperties() {
        let config = MoreTabConfiguration(
            headerSupportText: "Custom Text",
            showHelpOutSection: false,
            translateURL: URL(string: "https://translate.example.com"),
            developURL: nil,
            customLinks: []
        )

        XCTAssertEqual(config.headerSupportText, "Custom Text")
        XCTAssertFalse(config.showHelpOutSection)
        XCTAssertEqual(config.translateURL?.absoluteString, "https://translate.example.com")
        XCTAssertNil(config.developURL)
        XCTAssertTrue(config.customLinks.isEmpty)
    }
}
