//
//  AgencyAlert.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// A wrapper around a Protocol Buffer alert object. ProtoBuf is somewhat unpleasant to use directly,
/// and so this class offers some Swifty niceties on top of its jank.
public class AgencyAlert: NSObject {
    private let alert: TransitRealtime_Alert

    public let id: String

    // MARK: - Agency

    public let agencyID: String

    private static func findAgencyInList(list: [TransitRealtime_EntitySelector]) -> TransitRealtime_EntitySelector? {
        for sel in list where sel.hasAgencyID {
            return sel
        }
        return nil
    }

    public let agency: AgencyWithCoverage?

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

    public init(feedEntity: TransitRealtime_FeedEntity, agency: AgencyWithCoverage) throws {
        guard
            feedEntity.hasAlert,
            AgencyAlert.isAgencyWideAlert(alert: feedEntity.alert),
            let gtfsAgency = AgencyAlert.findAgencyInList(list: feedEntity.alert.informedEntity),
            gtfsAgency.hasAgencyID,
            gtfsAgency.agencyID == agency.agencyID
        else {
            throw AlertError.invalidAlert
        }
        alert = feedEntity.alert
        id = feedEntity.id
        agencyID = gtfsAgency.agencyID
        self.agency = agency
    }

    override public var hash: Int {
        return String(format: "%@_%@_%@", id, agencyID, title(language: "en") ?? "").hashValue
    }
}

// MARK: - Errors
extension AgencyAlert {
    enum AlertError: Error {
        case invalidAlert
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
    public func url(language: String) -> URL? {
        guard
            alert.hasURL,
            let urlString = translation(key: language, from: urlTranslations)
            else {
                return nil
        }

        return URL(string: urlString)
    }

    public func title(language: String) -> String? {
        guard alert.hasHeaderText else {
            return nil
        }

        return translation(key: language, from: titleTranslations)
    }

    public func body(language: String) -> String? {
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
        if let translation = map["en"] {
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
