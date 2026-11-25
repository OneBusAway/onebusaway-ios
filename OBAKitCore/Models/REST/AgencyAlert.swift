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
///
/// Every stored property is set in `init` and never mutated, which is what makes the
/// `@unchecked Sendable` conformance sound (`@unchecked` only because NSObject is not Sendable).
public final class AgencyAlert: NSObject, Identifiable, @unchecked Sendable {
    private let alert: TransitRealtime_Alert
    public let id: String

    /// Alert IDs that have already logged a corrupt active-period warning.
    /// Guards the once-per-alert log in `normalizedBounds(for:logCorrupt:)`.
    private static let corruptWarningLock = NSLock()
    private static nonisolated(unsafe) var warnedCorruptAlertIDs = Set<String>()

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

    /// The agency this alert applies to, or `nil` for a region-wide alert.
    public let agency: AgencyWithCoverage?

    /// `true` when this alert applies to the whole region rather than a single agency.
    public var isRegionWide: Bool { agency == nil }

    // MARK: - Localized Content Accessors

    public func title(preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
        resolveTitle(preferredLanguages: preferredLanguages, fallbackLocale: nil)
    }

    public func title(forLocale locale: Locale) -> String? {
        resolveTitle(preferredLanguages: Locale.preferredLanguages, fallbackLocale: locale)
    }

    public func title(forLocale locale: Locale, preferredLanguages: [String]) -> String? {
        resolveTitle(preferredLanguages: preferredLanguages, fallbackLocale: locale)
    }

    public func body(preferredLanguages: [String] = Locale.preferredLanguages) -> String? {
        resolveBody(preferredLanguages: preferredLanguages, fallbackLocale: nil)
    }

    public func body(forLocale locale: Locale) -> String? {
        resolveBody(preferredLanguages: Locale.preferredLanguages, fallbackLocale: locale)
    }

    public func body(forLocale locale: Locale, preferredLanguages: [String]) -> String? {
        resolveBody(preferredLanguages: preferredLanguages, fallbackLocale: locale)
    }

    public func url(preferredLanguages: [String] = Locale.preferredLanguages) -> URL? {
        resolveURL(preferredLanguages: preferredLanguages, fallbackLocale: nil)
    }

    public func url(forLocale locale: Locale) -> URL? {
        resolveURL(preferredLanguages: Locale.preferredLanguages, fallbackLocale: locale)
    }

    public func url(forLocale locale: Locale, preferredLanguages: [String]) -> URL? {
        resolveURL(preferredLanguages: preferredLanguages, fallbackLocale: locale)
    }

    private func candidateLanguages(preferredLanguages: [String], fallbackLocale: Locale?) -> [String] {
        var languages: [String] = []
        for lang in preferredLanguages {
            let trimmed = lang.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !languages.contains(trimmed) {
                languages.append(trimmed)
            }
        }
        if let fallbackLocale {
            let fullTag = fallbackLocale.identifier.replacingOccurrences(of: "_", with: "-")
            if !fullTag.isEmpty && !languages.contains(fullTag) {
                languages.append(fullTag)
            }
            if let code = fallbackLocale.language.languageCode?.identifier, !code.isEmpty && !languages.contains(code) {
                languages.append(code)
            }
        }
        return languages
    }

    private let defaultLanguageCode = "en"

    // MARK: - Initialization

    public convenience init(feedEntity: TransitRealtime_FeedEntity, agencies: [AgencyWithCoverage]) throws {
        guard
            let gtfsAgency = AgencyAlert.findAgencyInList(list: feedEntity.alert.informedEntity),
            gtfsAgency.hasAgencyID
        else {
            throw AlertError.invalidAlert
        }

        let selectedAgency = agencies.first { $0.agencyID == gtfsAgency.agencyID }

        // Obaco marks region-wide alerts — ones that apply to every agency in the
        // region rather than to one in particular — with an empty agency ID.
        guard selectedAgency != nil || gtfsAgency.agencyID.isEmpty else {
            throw AlertError.unknownAgency
        }

        try self.init(feedEntity: feedEntity, agency: selectedAgency)
    }

    public init(feedEntity: TransitRealtime_FeedEntity, agency: AgencyWithCoverage?) throws {
        guard
            feedEntity.hasAlert,
            AgencyAlert.isAgencyWideAlert(alert: feedEntity.alert),
            let gtfsAgency = AgencyAlert.findAgencyInList(list: feedEntity.alert.informedEntity),
            gtfsAgency.hasAgencyID,
            // A region-wide alert (no agency) must carry the empty agency ID Obaco
            // uses to mark it; an agency-specific alert's ID must match its agency.
            agency == nil ? gtfsAgency.agencyID.isEmpty : gtfsAgency.agencyID == agency?.agencyID
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
        let props: [String: Any] = ["id": id as Any, "agencyID": agencyID as Any, "agency": (agency?.agency.name ?? "(nil)") as Any]
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

    /// Whether this alert has at least one `active_period` entry.
    public var hasActivePeriod: Bool {
        !alert.activePeriod.isEmpty
    }

    /// Whether this alert is active at the given date.
    ///
    /// An alert with **no** active periods is treated as always active, per the
    /// GTFS-RT spec: "If this field is not provided, the alert will be shown as
    /// long as it appears in the feed."
    ///
    /// Each active period follows GTFS-RT `TimeRange` half-open semantics
    /// (`[start, end)`): inclusive of `start` and exclusive of an explicitly
    /// present positive `end`. An omitted `end` or `end == 0` is treated as
    /// unbounded, matching feeds that encode "no end" as `0`. Any period with
    /// inverted bounds (`start > end` when `end > 0`) logs a warning and is
    /// treated as inactive without forming a `ClosedRange`.
    ///
    /// - Parameter date: The point in time to test against. Defaults to `now`.
    /// - Returns: `true` when at least one active period covers `date`, or when
    ///   the alert has no active periods at all.
    public func isActive(at date: Date = Date()) -> Bool {
        // No active periods ⇒ always active (GTFS-RT spec).
        guard !alert.activePeriod.isEmpty else { return true }

        return alert.activePeriod.contains { period in
            guard let bounds = normalizedBounds(for: period, logCorrupt: true) else {
                return false
            }
            return Self.isDate(date, within: bounds)
        }
    }

    /// Returns the most recent explicit start date among active periods
    /// covering `date`.
    func activeStartDate(at date: Date = Date()) -> Date? {
        latestStartDate { Self.isDate(date, within: $0) }
    }

    /// Returns the start date used to order this alert chronologically.
    ///
    /// Prefers the latest start date among periods currently active at `date`,
    /// falling back to the latest valid (non-inverted) explicit start date
    /// across all active periods.
    func sortStartDate(asOf date: Date = Date()) -> Date? {
        activeStartDate(at: date) ?? latestStartDate { _ in true }
    }

    private func latestStartDate(where predicate: ((start: Date, end: Date?)) -> Bool) -> Date? {
        alert.activePeriod.compactMap { period -> Date? in
            guard
                period.hasStart,
                let bounds = normalizedBounds(for: period, logCorrupt: false),
                predicate(bounds)
            else {
                return nil
            }
            return bounds.start
        }.max()
    }

    private func normalizedBounds(
        for period: TransitRealtime_TimeRange,
        logCorrupt: Bool
    ) -> (start: Date, end: Date?)? {
        let start = period.hasStart
            ? Date(timeIntervalSince1970: TimeInterval(period.start))
            : Date.distantPast

        // Some GTFS-RT producers serialize `end = 0` to mean "no end" rather
        // than omitting the field; treat `0` as unbounded so live alerts are
        // not hidden as having ended at the Unix epoch.
        let end: Date? = (period.hasEnd && period.end > 0)
            ? Date(timeIntervalSince1970: TimeInterval(period.end))
            : nil

        if let end, start > end {
            if logCorrupt {
                warnCorruptPeriod(period: period)
            }
            return nil
        }

        return (start, end)
    }

    /// Logs the corrupt-period warning for this alert only the first time an
    /// alert ID is seen, so repeated calls don't spam the log on every map
    /// refresh.
    private func warnCorruptPeriod(period: TransitRealtime_TimeRange) {
        Self.corruptWarningLock.lock()
        let isNewWarning = Self.warnedCorruptAlertIDs.insert(id).inserted
        Self.corruptWarningLock.unlock()

        guard isNewWarning else {
            return
        }

        Logger.warn(
            "AgencyAlert \(id): corrupt active period (start \(period.start) > end \(period.end)); treating as inactive."
        )
    }

    private static func isDate(_ date: Date, within bounds: (start: Date, end: Date?)) -> Bool {
        guard date >= bounds.start else {
            return false
        }
        if let end = bounds.end {
            // GTFS-RT TimeRange is active when start <= t < end.
            return date < end
        }
        return true
    }
}

// MARK: - Translated Text

extension AgencyAlert {
    private func languageCode(from identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier.lowercased() ?? identifier.lowercased()
    }

    private func resolveURL(preferredLanguages: [String], fallbackLocale: Locale?) -> URL? {
        guard
            alert.hasURL,
            let urlString = translation(
                preferredLanguages: candidateLanguages(preferredLanguages: preferredLanguages, fallbackLocale: fallbackLocale),
                from: alert.url.translation
            )
        else {
            return nil
        }

        return URL(string: urlString)
    }

    private func resolveTitle(preferredLanguages: [String], fallbackLocale: Locale?) -> String? {
        guard alert.hasHeaderText else {
            return nil
        }

        return translation(
            preferredLanguages: candidateLanguages(preferredLanguages: preferredLanguages, fallbackLocale: fallbackLocale),
            from: alert.headerText.translation
        )
    }

    private func resolveBody(preferredLanguages: [String], fallbackLocale: Locale?) -> String? {
        guard alert.hasDescriptionText else {
            return nil
        }

        return translation(
            preferredLanguages: candidateLanguages(preferredLanguages: preferredLanguages, fallbackLocale: fallbackLocale),
            from: alert.descriptionText.translation
        )
    }

    fileprivate func url(language: String) -> URL? {
        resolveURL(preferredLanguages: [language], fallbackLocale: nil)
    }

    fileprivate func title(language: String) -> String? {
        resolveTitle(preferredLanguages: [language], fallbackLocale: nil)
    }

    fileprivate func body(language: String) -> String? {
        resolveBody(preferredLanguages: [language], fallbackLocale: nil)
    }

    // A linear scan over the stored protobuf (translation lists hold a handful
    // of entries at most): pure reads of immutable `let` state, so there is
    // nothing to cache or synchronize.
    private func translation(
        preferredLanguages: [String],
        from translations: [TransitRealtime_TranslatedString.Translation]
    ) -> String? {
        guard !translations.isEmpty else { return nil }

        let normalizedLangs = preferredLanguages.map { $0.replacingOccurrences(of: "_", with: "-") }

        // 1. Language matching using Bundle.preferredLocalizations.
        // Evaluates preferred languages in priority order, matching exact tags as well as dialect
        // and script fallbacks (e.g. "es-MX" -> "es", "zh-Hant-TW" -> "zh-Hant").
        let availableLangs = translations.map { $0.language.replacingOccurrences(of: "_", with: "-") }
        let matchedLangs = Bundle.preferredLocalizations(from: availableLangs, forPreferences: normalizedLangs)
        for matched in matchedLangs {
            if let match = translations.first(where: {
                $0.language.replacingOccurrences(of: "_", with: "-").caseInsensitiveCompare(matched) == .orderedSame
            }) {
                return match.text
            }
        }

        // Steps 2-4 run only when `Bundle.preferredLocalizations` returns an empty array
        // (e.g. if `normalizedLangs` is empty, or on platforms/environments where localization resolution behaves strictly).

        // 2. Base language identifier fallback (e.g. "es", "fr", "zh") across preferred languages in order
        for pref in normalizedLangs {
            let prefCode = languageCode(from: pref)
            guard !prefCode.isEmpty else { continue }
            if let match = translations.first(where: {
                let transCode = languageCode(from: $0.language)
                return !transCode.isEmpty && transCode == prefCode
            }) {
                return match.text
            }
        }

        // 3. Fall back to English ("en")
        if let exactEn = translations.first(where: {
            $0.language.caseInsensitiveCompare(defaultLanguageCode) == .orderedSame ||
            languageCode(from: $0.language) == defaultLanguageCode
        }) {
            return exactEn.text
        }

        // 4. Fall back to raw / first translation
        return translations.first?.text
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

    /// Whether this alert applies to the given stop.
    public func applies(to stop: Stop) -> Bool {
        if isRegionWide { return true }
        if let routes = stop.routes {
            return routes.contains { $0.agencyID == agencyID || $0.agency?.id == agencyID }
        }
        return stop.id.hasPrefix("\(agencyID)_")
    }
}
