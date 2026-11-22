//
//  AgencyAlertTranslationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Pins the translation-selection semantics of `AgencyAlert`:
/// exact language match → English → first entry in feed order.
///
/// The fallback tiers matter because GTFS-RT feeds routinely carry only a
/// subset of languages, and the final tier must be deterministic — it used to
/// be backed by a dictionary, whose arbitrary ordering made "whatever we can
/// get our hands on" vary between processes.
@Suite(.serialized)
final class AgencyAlertTranslationTests: OBATestCase {

    private func translation(_ language: String, _ text: String) -> TransitRealtime_TranslatedString.Translation {
        var t = TransitRealtime_TranslatedString.Translation()
        t.language = language
        t.text = text
        return t
    }

    /// Builds a region-wide alert (no agency needed) whose header carries `translations`.
    private func makeAlert(
        headerTranslations: [TransitRealtime_TranslatedString.Translation],
        bodyTranslations: [TransitRealtime_TranslatedString.Translation] = [],
        urlTranslations: [TransitRealtime_TranslatedString.Translation] = []
    ) throws -> AgencyAlert {
        var period = TransitRealtime_TimeRange()
        period.start = UInt64(Date().timeIntervalSince1970)

        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

        var header = TransitRealtime_TranslatedString()
        header.translation = headerTranslations

        var body = TransitRealtime_TranslatedString()
        body.translation = bodyTranslations

        var url = TransitRealtime_TranslatedString()
        url.translation = urlTranslations

        var alert = TransitRealtime_Alert()
        alert.severityLevel = .warning
        alert.activePeriod = [period]
        alert.informedEntity = [entitySelector]
        alert.headerText = header
        if !bodyTranslations.isEmpty {
            alert.descriptionText = body
        }
        if !urlTranslations.isEmpty {
            alert.url = url
        }

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = "Alert_1"
        feedEntity.alert = alert

        return try AgencyAlert(feedEntity: feedEntity, agency: nil)
    }

    @Test func `Exact language match wins`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("en", "English title"),
            translation("fr", "Titre français")
        ])

        #expect(alert.title(preferredLanguages: ["fr"]) == "Titre français")
    }

    @Test func `Missing language falls back to english`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("fr", "Titre français"),
            translation("en", "English title")
        ])

        #expect(alert.title(preferredLanguages: ["es"]) == "English title")
    }

    @Test func `Missing language and english falls back to first entry in feed order`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("fr", "Titre français"),
            translation("de", "Deutscher Titel")
        ])

        #expect(alert.title(preferredLanguages: ["es"]) == "Titre français")
    }

    @Test func `Duplicate language entries first wins`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("en", "First English title"),
            translation("en", "Second English title")
        ])

        #expect(alert.title(preferredLanguages: ["en"]) == "First English title")
    }

    @Test func `forLocale matches exact dialect before base language`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("zh-Hans", "简体中文标题"),
            translation("zh-Hant", "繁體中文標題")
        ])

        #expect(alert.title(forLocale: Locale(identifier: "zh-Hant-TW"), preferredLanguages: ["zh-Hant-TW", "en-US"]) == "繁體中文標題")
        #expect(alert.title(forLocale: Locale(identifier: "zh-Hans-CN"), preferredLanguages: ["zh-Hans-CN", "en-US"]) == "简体中文标题")
    }

    @Test func `forLocale with Spanish dialect matches dialect before base language`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("es", "Título general"),
            translation("es-MX", "Título mexicano")
        ])

        #expect(alert.title(forLocale: Locale(identifier: "es-MX"), preferredLanguages: ["es-MX", "en-US"]) == "Título mexicano")
    }

    @Test func `Preferred language hierarchy matches first available language`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("es", "Título en español"),
            translation("fr", "Titre en français"),
            translation("de", "Deutscher Titel")
        ])

        #expect(alert.title(preferredLanguages: ["fr", "es"]) == "Titre en français")
        #expect(alert.title(preferredLanguages: ["es", "fr"]) == "Título en español")
    }

    @Test func `Preferred language dialect matches base language identifier`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("es", "Título en español"),
            translation("en", "English title")
        ])

        #expect(alert.title(preferredLanguages: ["es-MX", "en-US"]) == "Título en español")
    }

    @Test func `Preferred language exact dialect matches before base language identifier`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("es", "Título general"),
            translation("es-MX", "Título mexicano")
        ])

        #expect(alert.title(preferredLanguages: ["es-MX", "en-US"]) == "Título mexicano")
    }

    @Test func `Preferred language hierarchy skips unavailable language to next preferred`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("fr", "Titre en français"),
            translation("de", "Deutscher Titel")
        ])

        #expect(alert.title(preferredLanguages: ["ja", "de", "fr"]) == "Deutscher Titel")
    }

    @Test func `Preferred language hierarchy resolves body and URL`() throws {
        let alert = try makeAlert(
            headerTranslations: [
                translation("es", "Título en español"),
                translation("fr", "Titre en français")
            ],
            bodyTranslations: [
                translation("es", "Cuerpo en español"),
                translation("fr", "Corps en français")
            ],
            urlTranslations: [
                translation("es", "https://example.com/es"),
                translation("fr", "https://example.com/fr")
            ]
        )

        #expect(alert.body(preferredLanguages: ["fr", "es"]) == "Corps en français")
        #expect(alert.url(preferredLanguages: ["fr", "es"]) == URL(string: "https://example.com/fr"))
        #expect(alert.body(preferredLanguages: ["es", "fr"]) == "Cuerpo en español")
        #expect(alert.url(preferredLanguages: ["es", "fr"]) == URL(string: "https://example.com/es"))
    }

    @Test func `Preferred language falls back to English when no preferred languages match`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("en", "English title"),
            translation("de", "Deutscher Titel")
        ])

        #expect(alert.title(preferredLanguages: ["ja", "ko"]) == "English title")
    }

    @Test func `Preferred language falls back to first translation when neither preferred nor English match`() throws {
        let alert = try makeAlert(headerTranslations: [
            translation("de", "Deutscher Titel"),
            translation("it", "Titolo italiano")
        ])

        #expect(alert.title(preferredLanguages: ["ja", "ko"]) == "Deutscher Titel")
    }
}
