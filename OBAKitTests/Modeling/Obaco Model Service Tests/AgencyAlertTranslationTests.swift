//
//  AgencyAlertTranslationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

/// Pins the translation-selection semantics of `AgencyAlert`:
/// exact language match → English → first entry in feed order.
///
/// The fallback tiers matter because GTFS-RT feeds routinely carry only a
/// subset of languages, and the final tier must be deterministic — it used to
/// be backed by a dictionary, whose arbitrary ordering made "whatever we can
/// get our hands on" vary between processes.
class AgencyAlertTranslationTests: OBATestCase {

    private func translation(_ language: String, _ text: String) -> TransitRealtime_TranslatedString.Translation {
        var t = TransitRealtime_TranslatedString.Translation()
        t.language = language
        t.text = text
        return t
    }

    /// Builds a region-wide alert (no agency needed) whose header carries `translations`.
    private func makeAlert(headerTranslations: [TransitRealtime_TranslatedString.Translation]) throws -> AgencyAlert {
        var period = TransitRealtime_TimeRange()
        period.start = UInt64(Date().timeIntervalSince1970)

        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

        var header = TransitRealtime_TranslatedString()
        header.translation = headerTranslations

        var alert = TransitRealtime_Alert()
        alert.severityLevel = .warning
        alert.activePeriod = [period]
        alert.informedEntity = [entitySelector]
        alert.headerText = header

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = "Alert_1"
        feedEntity.alert = alert

        return try AgencyAlert(feedEntity: feedEntity, agency: nil)
    }

    func test_exactLanguageMatch_wins() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("en", "English title"),
            translation("fr", "Titre français")
        ])

        XCTAssertEqual(alert.title(forLocale: Locale(identifier: "fr_FR")), "Titre français")
    }

    func test_missingLanguage_fallsBackToEnglish() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("fr", "Titre français"),
            translation("en", "English title")
        ])

        XCTAssertEqual(alert.title(forLocale: Locale(identifier: "es_ES")), "English title")
    }

    func test_missingLanguageAndEnglish_fallsBackToFirstEntryInFeedOrder() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("fr", "Titre français"),
            translation("de", "Deutscher Titel")
        ])

        XCTAssertEqual(alert.title(forLocale: Locale(identifier: "es_ES")), "Titre français")
    }

    func test_duplicateLanguageEntries_firstWins() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("en", "First English title"),
            translation("en", "Second English title")
        ])

        XCTAssertEqual(alert.title(forLocale: Locale(identifier: "en_US")), "First English title")
    }
}
