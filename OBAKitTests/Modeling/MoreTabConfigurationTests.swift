//
//  MoreTabConfigurationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class MoreTabConfigurationTests {

    // MARK: - Default Configuration

    @Test func `Default configuration has expected values`() {
        let config = MoreTabConfiguration.default
        #expect(config.headerSupportText == nil)
        #expect(config.showHelpOutSection)
        #expect(config.translateURL == nil)
        #expect(config.developURL?.absoluteString == "https://github.com/oneBusAway/onebusaway-ios")
        #expect(config.tutorialURL == nil)
        #expect(config.phoneURL == nil)
        #expect(config.textURL == nil)
        #expect(config.customLinks.isEmpty)
    }

    // MARK: - Parsing from Dictionary

    @Test func `Parse from dictionary with all fields`() {
        let dict: [AnyHashable: Any] = [
            "HeaderSupportText": "Powered by TestAgency",
            "ShowHelpOutSection": false,
            "TranslateURL": "https://example.com/translate",
            "DevelopURL": "https://example.com/develop",
            "TutorialURL": "https://example.com/tutorials",
            "PhoneURL": "tel:+1234567890",
            "TextURL": "sms:+1234567890",
            "CustomLinks": [
                ["Title": "Agency Site", "URL": "https://example.com"],
                ["Title": "Call Us", "URL": "tel:+1234567890"]
            ]
        ]

        let config = MoreTabConfiguration(from: dict)

        #expect(config.headerSupportText == "Powered by TestAgency")
        #expect(!config.showHelpOutSection)
        #expect(config.translateURL?.absoluteString == "https://example.com/translate")
        #expect(config.developURL?.absoluteString == "https://example.com/develop")
        #expect(config.tutorialURL?.absoluteString == "https://example.com/tutorials")
        #expect(config.phoneURL?.absoluteString == "tel:+1234567890")
        #expect(config.textURL?.absoluteString == "sms:+1234567890")
        #expect(config.customLinks.count == 2)
        #expect(config.customLinks[0].title == "Agency Site")
        #expect(config.customLinks[0].url.absoluteString == "https://example.com")
        #expect(config.customLinks[1].title == "Call Us")
        #expect(config.customLinks[1].url.absoluteString == "tel:+1234567890")
    }

    @Test func `Parse ignores empty agency contact URLs`() {
        let dict: [AnyHashable: Any] = [
            "TutorialURL": "",
            "PhoneURL": "",
            "TextURL": ""
        ]
        let config = MoreTabConfiguration(from: dict)
        #expect(config.tutorialURL == nil)
        #expect(config.phoneURL == nil)
        #expect(config.textURL == nil)
    }

    @Test func `Parse from dictionary with minimal fields`() {
        let dict: [AnyHashable: Any] = [:]
        let config = MoreTabConfiguration(from: dict)

        #expect(config.headerSupportText == nil)
        #expect(config.showHelpOutSection)
        #expect(config.translateURL == nil)
        #expect(config.developURL?.absoluteString == "https://github.com/oneBusAway/onebusaway-ios")
        #expect(config.customLinks.isEmpty)
    }

    @Test func `Parse from dictionary with partial fields`() {
        let dict: [AnyHashable: Any] = [
            "ShowHelpOutSection": false,
            "TranslateURL": "https://custom-translate.com"
        ]
        let config = MoreTabConfiguration(from: dict)

        #expect(config.headerSupportText == nil)
        #expect(!config.showHelpOutSection)
        #expect(config.translateURL?.absoluteString == "https://custom-translate.com")
        #expect(config.developURL?.absoluteString == "https://github.com/oneBusAway/onebusaway-ios")
        #expect(config.customLinks.isEmpty)
    }

    // MARK: - MoreTabLinkItem

    @Test func `Link item valid dictionary succeeds`() {
        let dict: [AnyHashable: Any] = [
            "Title": "Test Link",
            "URL": "https://example.com"
        ]
        let item = MoreTabLinkItem(dictionary: dict)

        #expect(item != nil)
        #expect(item?.title == "Test Link")
        #expect(item?.url.absoluteString == "https://example.com")
    }

    @Test func `Link item missing title returns nil`() {
        let dict: [AnyHashable: Any] = ["URL": "https://example.com"]
        #expect(MoreTabLinkItem(dictionary: dict) == nil)
    }

    @Test func `Link item missing URL returns nil`() {
        let dict: [AnyHashable: Any] = ["Title": "Test"]
        #expect(MoreTabLinkItem(dictionary: dict) == nil)
    }

    @Test func `Link item empty URL returns nil`() {
        let dict: [AnyHashable: Any] = ["Title": "Test", "URL": ""]
        #expect(MoreTabLinkItem(dictionary: dict) == nil)
    }

    @Test func `Link item malformed links filtered in configuration`() {
        let dict: [AnyHashable: Any] = [
            "CustomLinks": [
                ["Title": "Valid", "URL": "https://example.com"],
                ["Title": "Missing URL"],
                ["URL": "https://no-title.com"],
                ["Title": "Empty URL", "URL": ""]
            ]
        ]
        let config = MoreTabConfiguration(from: dict)
        #expect(config.customLinks.count == 1)
        #expect(config.customLinks[0].title == "Valid")
        #expect(config.customLinks[0].url.absoluteString == "https://example.com")
    }

    // MARK: - Direct Initializer

    @Test func `Direct initializer sets all properties`() {
        let config = MoreTabConfiguration(
            headerSupportText: "Custom Text",
            showHelpOutSection: false,
            translateURL: URL(string: "https://translate.example.com"),
            developURL: nil,
            customLinks: []
        )

        #expect(config.headerSupportText == "Custom Text")
        #expect(!config.showHelpOutSection)
        #expect(config.translateURL?.absoluteString == "https://translate.example.com")
        #expect(config.developURL == nil)
        #expect(config.customLinks.isEmpty)
    }
}
