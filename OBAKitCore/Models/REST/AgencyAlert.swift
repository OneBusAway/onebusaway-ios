//
//  AgencyAlert.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A wrapper around a Protocol Buffer alert object. ProtoBuf is somewhat unpleasant to use directly,
/// and so this class offers some Swifty niceties on top of its jank.
public class AgencyAlert: NSObject, Identifiable {
    private let alert: TransitRealtime_Alert
    public let id: String

    public var isHighSeverity: Bool {
        guard alert.hasSeverityLevel else {
            return false
        }

        return alert.severityLevel == .severe || alert.severityLevel == .warning
    }

    // MARK: - Agency

    public let agencyID: String

    private static func findAgencyInList(list: [TransitRealtime_EntitySelector]) -> TransitRealtime_EntitySelector? {
        for sel in list where sel.hasAgencyID {
            return sel
        }
        return nil
    }

    public let agency: AgencyWithCoverage?

    // MARK: - Localized Content Accessors

    public func title(forLocale locale: Locale) -> String? {
        return title(language: selectLanguageCode(locale: locale)) ?? title(language: defaultLanguageCode)
    }

    public func body(forLocale locale: Locale) -> String? {
        return body(language: selectLanguageCode(locale: locale)) ?? body(language: defaultLanguageCode)
    }

    public func url(forLocale locale: Locale) -> URL? {
        url(language: selectLanguageCode(locale: locale)) ?? url(language: defaultLanguageCode)
    }

    private func selectLanguageCode(locale: Locale) -> String {
        locale.languageCode ?? defaultLanguageCode
    }

    private let defaultLanguageCode = "en"

    // MARK: - Translation Properties

    private lazy var urlTranslations: [String: String] = {
        return alert.url.translation.reduce(into: [:]) { (acc, translation) in
            acc[translation.language] = translation.text
        }
    }()

    private lazy var titleTranslations: [String: String] = {
        return alert.headerText.translation.reduce(into: [:]) { (acc, translation) in
            acc[translation.language] = translation.text
        }
    }()

    private lazy var bodyTranslations: [String: String] = {
        return alert.descriptionText.translation.reduce(into: [:]) { (acc, translation) in
            acc[translation.language] = translation.text
        }
    }()

    // MARK: - Initialization

    public convenience init(feedEntity: TransitRealtime_FeedEntity, agencies: [AgencyWithCoverage]) throws {
        guard
            let gtfsAgency = AgencyAlert.findAgencyInList(list: feedEntity.alert.informedEntity),
            gtfsAgency.hasAgencyID
        else {
            throw AlertError.invalidAlert
        }

        guard let selectedAgency = agencies.filter({ $0.id == gtfsAgency.agencyID }).first else {
            throw AlertError.unknownAgency
        }

        try self.init(feedEntity: feedEntity, agency: selectedAgency)
    }

    public init(feedEntity: TransitRealtime_FeedEntity, agency: AgencyWithCoverage) throws {
        guard
            feedEntity.hasAlert,
            AgencyAlert.isAgencyWideAlert(alert: feedEntity.alert),
            let gtfsAgency = AgencyAlert.findAgencyInList(list: feedEntity.alert.informedEntity),
            gtfsAgency.hasAgencyID,
            gtfsAgency.agencyID == agency.id
        else {
            throw AlertError.invalidAlert
        }
        alert = feedEntity.alert
        id = feedEntity.id
        agencyID = gtfsAgency.agencyID
        self.agency = agency
    }

    // MARK: - Equality and Hashing

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? AgencyAlert else { return false }
        return alert == rhs.alert &&
               id == rhs.id &&
               agencyID == rhs.agencyID &&
               agency == rhs.agency
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(alert)
        hasher.combine(id)
        hasher.combine(agencyID)
        hasher.combine(agency)
        return hasher.finalize()
    }

    override public var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = [
            "id": id as Any,
            "agencyID": agencyID as Any
        ]
        return "\(desc) \(props)"
    }
}

// MARK: - Errors

extension AgencyAlert {
    enum AlertError: Error {
        case invalidAlert, unknownAgency
    }
}

// MARK: - Timeframes

extension AgencyAlert {
    public var startDate: Date? {
        guard
            let period = alert.activePeriod.first,
            period.hasStart
            else {
                return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(period.start))
    }

    public var endDate: Date? {
        guard
            let period = alert.activePeriod.first,
            period.hasEnd
            else {
                return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(period.end))
    }
}

// MARK: - Translated Text

extension AgencyAlert {
    fileprivate func url(language: String) -> URL? {
        guard
            alert.hasURL,
            let urlString = translation(key: language, from: urlTranslations)
            else {
                return nil
        }

        return URL(string: urlString)
    }

    fileprivate func title(language: String) -> String? {
        guard alert.hasHeaderText else {
            return nil
        }

        return translation(key: language, from: titleTranslations)
    }

    fileprivate func body(language: String) -> String? {
        guard alert.hasDescriptionText else {
            return nil
        }

        return translation(key: language, from: bodyTranslations)
    }

    private func translation(key: String, from map: [String: String]) -> String? {
        if let translation = map[key] {
            return translation
        }

        // If we don't have the desired translation, first check
        // to see if we have a default translation language value
        // present. For now this is English.
        if let translation = map[defaultLanguageCode] {
            return translation
        }

        // If that doesn't work out and we don't have our
        // desired language or default language, then just
        // return whatever we can get our hands on.
        if let key = map.keys.first {
            return map[key]
        }
        else {
            return nil
        }
    }
}

// MARK: - Static Helpers

extension AgencyAlert {
    public static func isAgencyWideAlert(alert: TransitRealtime_Alert) -> Bool {
        for sel in alert.informedEntity where sel.hasAgencyID {
            return true
        }

        return false
    }
}
