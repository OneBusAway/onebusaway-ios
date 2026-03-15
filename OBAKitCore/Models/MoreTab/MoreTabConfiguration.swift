//
//  MoreTabConfiguration.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Represents a customizable link item in the More tab.
public struct MoreTabLinkItem {
    public let title: String
    public let url: URL

    /// Failable initializer — returns nil if title or URL is missing/invalid.
    public init?(dictionary: [AnyHashable: Any]) {
        guard
            let title = dictionary["Title"] as? String,
            let urlString = dictionary["URL"] as? String,
            let url = URL(string: urlString),
            !urlString.isEmpty
        else { return nil }

        self.title = title
        self.url = url
    }
}

/// Configuration for the More tab, read from OBAKitConfig.MoreTab in Info.plist.
public struct MoreTabConfiguration {

    /// Custom support text shown in header. nil = use default localized string.
    public let headerSupportText: String?

    /// Whether to show the "Help Out" section (Translate/Develop links). Default: true.
    public let showHelpOutSection: Bool

    /// Custom URL for "Help Translate" link. nil = hide the row.
    public let translateURL: URL?

    /// Custom URL for "Help Develop" link. nil = hide the row.
    public let developURL: URL?

    /// Additional custom link items displayed in a "Resources" section.
    public let customLinks: [MoreTabLinkItem]

    /// Default configuration matching current hardcoded behavior.
    public static let `default` = MoreTabConfiguration(
        headerSupportText: nil,
        showHelpOutSection: true,
        translateURL: URL(string: "https://www.transifex.com/open-transit-software-foundation/onebusaway-ios/"),
        developURL: URL(string: "https://github.com/oneBusAway/onebusaway-ios"),
        customLinks: []
    )

    /// Parse from Info.plist dictionary. Falls back to defaults for missing keys.
    public init(from dictionary: [AnyHashable: Any]) {
        self.headerSupportText = dictionary["HeaderSupportText"] as? String

        self.showHelpOutSection = (dictionary["ShowHelpOutSection"] as? Bool) ?? true

        if let urlString = dictionary["TranslateURL"] as? String {
            self.translateURL = URL(string: urlString)
        } else {
            self.translateURL = MoreTabConfiguration.default.translateURL
        }

        if let urlString = dictionary["DevelopURL"] as? String {
            self.developURL = URL(string: urlString)
        } else {
            self.developURL = MoreTabConfiguration.default.developURL
        }

        if let linksArray = dictionary["CustomLinks"] as? [[AnyHashable: Any]] {
            self.customLinks = linksArray.compactMap { MoreTabLinkItem(dictionary: $0) }
        } else {
            self.customLinks = []
        }
    }

    public init(
        headerSupportText: String?,
        showHelpOutSection: Bool,
        translateURL: URL?,
        developURL: URL?,
        customLinks: [MoreTabLinkItem]
    ) {
        self.headerSupportText = headerSupportText
        self.showHelpOutSection = showHelpOutSection
        self.translateURL = translateURL
        self.developURL = developURL
        self.customLinks = customLinks
    }
}
