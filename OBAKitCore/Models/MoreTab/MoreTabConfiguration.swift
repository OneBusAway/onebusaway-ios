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
public struct MoreTabLinkItem: Sendable {
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
public struct MoreTabConfiguration: Sendable {

    /// Custom support text shown in header. nil = use default localized string.
    public let headerSupportText: String?

    /// Whether to show the "Help Out" section (Translate/Develop links). Default: true.
    public let showHelpOutSection: Bool

    /// Custom URL for "Help Translate" link. nil = hide the row.
    public let translateURL: URL?

    /// Custom URL for "Help Develop" link. nil = hide the row.
    public let developURL: URL?

    /// Optional tutorial / user-manual page. Shown as "Tutorials" when set (#614).
    public let tutorialURL: URL?

    /// Optional `tel:` (or https) URL to call the agency. Shown as "Call Agency" when set (#614).
    public let phoneURL: URL?

    /// Optional `sms:` (or https) URL for an agency text service. Shown as "Text Agency" when set (#614).
    public let textURL: URL?

    /// Additional custom link items displayed in a "Resources" section.
    public let customLinks: [MoreTabLinkItem]

    /// Default configuration matching current hardcoded behavior.
    /// `translateURL` defaults to nil, which hides the "Translate the App" row;
    /// white-label apps can opt in by setting `TranslateURL` in their config.
    public static let `default` = MoreTabConfiguration(
        headerSupportText: nil,
        showHelpOutSection: true,
        translateURL: nil,
        developURL: URL(string: "https://github.com/oneBusAway/onebusaway-ios"),
        tutorialURL: nil,
        phoneURL: nil,
        textURL: nil,
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

        self.tutorialURL = Self.url(from: dictionary, key: "TutorialURL")
        self.phoneURL = Self.url(from: dictionary, key: "PhoneURL")
        self.textURL = Self.url(from: dictionary, key: "TextURL")

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
        tutorialURL: URL? = nil,
        phoneURL: URL? = nil,
        textURL: URL? = nil,
        customLinks: [MoreTabLinkItem]
    ) {
        self.headerSupportText = headerSupportText
        self.showHelpOutSection = showHelpOutSection
        self.translateURL = translateURL
        self.developURL = developURL
        self.tutorialURL = tutorialURL
        self.phoneURL = phoneURL
        self.textURL = textURL
        self.customLinks = customLinks
    }

    private static func url(from dictionary: [AnyHashable: Any], key: String) -> URL? {
        guard let urlString = dictionary[key] as? String, !urlString.isEmpty else {
            return nil
        }
        return URL(string: urlString)
    }
}
