//
//  LocalizationTests.swift
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

/// Guards the localization data itself, which is bulk-imported a hundred-plus keys at a
/// time and therefore drifts in ways no other test would notice: a missing key silently
/// falls back to English, and a mismatched format specifier makes `String(format:)` read
/// past its argument list.
@MainActor
@Suite(.serialized)
final class LocalizationTests {

    /// Keys whose plural forms come from `Localizable.stringsdict` rather than
    /// `Localizable.strings`. Each is called with a count.
    ///
    /// Note that `String(format:)` expands `%#@…@` but always resolves it against the root
    /// plural rule, so only `one`/`other` are ever reachable through it — the call site has to
    /// use `String.localizedStringWithFormat` for a locale's `few`/`many`/`zero`/`two` entries
    /// to mean anything. The parity checks below can't see that; it's a call-site property.
    /// A test *can* pin it per key by asserting a locale whose categories differ from the
    /// root's — see `Polish layer count reaches its few and many forms`.
    private static let pluralKeys: Set<String> = [
        "stop_page.service_alerts.summary_fmt",
        "stop_page.service_alerts.show_all_fmt",
        "stop_page.timeline.skipped_stops_fmt",
        "stop_page.past_toggle_show_a11y_fmt",
        "stop_controller.transfer_show_earlier_departures_fmt",
        "stop_page.empty.no_departures_fmt",
        "data_migration_bulletin.report_summary_number_of_failures",
        "data_migration_bulletin.report_summary_number_of_successes",
        "map_controller.map_type.accessibility_value_with_layers_fmt",
        "search_results_sheet.result_count_fmt"
    ]

    /// `%@`, `%d`, `%1$@`, `%2$d`, … and the escaped `%%`.
    // swiftlint:disable:next force_try
    private static let specifier = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dfs]|%%"#)

    private var frameworks: [(name: String, bundle: Bundle)] {
        [("OBAKit", Bundle(for: DonationCell.self)),
         ("OBAKitCore", Bundle(for: Strings.self))]
    }

    private func strings(in bundle: Bundle, localization: String) -> [String: String]? {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings",
                                   subdirectory: nil, localization: localization) else { return nil }
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    /// A named locale's own copy of a key, loaded by treating its `.lproj` as a bundle —
    /// the only way to read a localization the test host doesn't prefer. Going through
    /// `localizedString(forKey:)` matters: it keeps the `Localizable.stringsdict` rules
    /// attached to the returned format, which parsing the plist by hand would not.
    private func localizedFormat(forKey key: String, localization: String) -> String? {
        guard let path = Bundle(for: DonationCell.self).path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }

        let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
        return value == "MISSING" ? nil : value
    }

    private func specifiers(in value: String) -> [String] {
        let range = NSRange(value.startIndex..., in: value)
        return Self.specifier.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }

    // MARK: - Key parity

    /// A key missing from a locale silently renders in English. Nothing else catches it.
    @Test func `Every locale has same keys as english`() {
        for (name, bundle) in frameworks {
            guard let english = strings(in: bundle, localization: "en") else {
                Issue.record("\(name): no en Localizable.strings")
                return
            }
            #expect(english.count > 100, "\(name): en table looks truncated")

            for localization in bundle.localizations where localization != "en" && localization != "Base" {
                guard let translated = strings(in: bundle, localization: localization) else { continue }
                let missing = Set(english.keys).subtracting(translated.keys)
                let extra = Set(translated.keys).subtracting(english.keys)
                #expect(missing.isEmpty, "\(name)/\(localization) is missing \(missing.count) key(s): \(missing.sorted().prefix(5))")
                #expect(extra.isEmpty, "\(name)/\(localization) has \(extra.count) key(s) not in en: \(extra.sorted().prefix(5))")
            }
        }
    }

    // MARK: - Format specifier parity

    /// A translation that drops `%@` silently renders without the app name; one that *adds*
    /// a specifier makes `String(format:)` read past the end of its arguments.
    @Test func `Every locale preserves english format specifiers`() {
        for (name, bundle) in frameworks {
            guard let english = strings(in: bundle, localization: "en") else { continue }

            for localization in bundle.localizations where localization != "en" && localization != "Base" {
                guard let translated = strings(in: bundle, localization: localization) else { continue }
                for (key, translation) in translated {
                    guard let source = english[key] else { continue }
                    #expect(specifiers(in: source) == specifiers(in: translation), "\(name)/\(localization)/\(key): format specifiers differ from English — en=\(source) \(localization)=\(translation)")
                }
            }
        }
    }

    // MARK: - stringsdict

    /// Every locale must carry all the plural keys, with the CLDR-mandatory `other` category.
    /// A dropped entry degrades silently to the `.strings` fallback ("1 stops").
    @Test func `Every locale stringsdict is well formed`() {
        let bundle = Bundle(for: DonationCell.self)

        for localization in bundle.localizations where localization != "Base" {
            guard let url = bundle.url(forResource: "Localizable", withExtension: "stringsdict",
                                       subdirectory: nil, localization: localization),
                  let dict = NSDictionary(contentsOf: url) as? [String: Any]
            else {
                Issue.record("\(localization): Localizable.stringsdict is missing or unparseable")
                return
            }

            let missing = Self.pluralKeys.subtracting(dict.keys)
            #expect(missing.isEmpty, "\(localization)/stringsdict is missing \(missing.sorted())")

            for key in Self.pluralKeys {
                guard let entry = dict[key] as? [String: Any],
                      let variable = entry["count"] as? [String: Any]
                else {
                    Issue.record("\(localization)/\(key): malformed stringsdict entry")
                    continue
                }
                #expect((variable["NSStringFormatSpecTypeKey"] as? String) == "NSStringPluralRuleType", "\(localization)/\(key): wrong spec type")
                #expect(variable["other"] != nil, "\(localization)/\(key): missing mandatory CLDR category 'other'")
            }
        }
    }

    /// The footer names the switch. A locale that leaves the English phrase in
    /// the footer while translating the title makes the two unrecognizable as
    /// the same control.
    @Test func `Transfer banner footer names the switch title in every locale`() {
        let bundle = Bundle(for: DonationCell.self)
        let titleKey = "settings_controller.arrival_display_section.transfer_banner"
        let footerKey = "settings_controller.arrival_display_section.transfer_banner.footer"

        for localization in bundle.localizations where localization != "Base" {
            guard let table = strings(in: bundle, localization: localization),
                  let title = table[titleKey],
                  let footer = table[footerKey] else {
                Issue.record("\(localization): missing transfer banner strings")
                continue
            }
            #expect(footer.hasPrefix(title), "\(localization): footer must start with the switch title \"\(title)\"")
        }
    }

    /// The plural keys exist in *both* `Localizable.strings` (as the `value:` fallback) and
    /// `Localizable.stringsdict`. If the stringsdict resource ever stops being bundled, lookup
    /// silently falls back to the bare `%d` form and English renders "1 stops". Assert the
    /// singular actually resolves, which only happens when the stringsdict is present.
    @Test func `Stringsdict is bundled so singulars resolve`() {
        let bundle = Bundle(for: DonationCell.self)
        let expectedSingulars = [
            "stop_page.timeline.skipped_stops_fmt": "1 stop",
            "stop_page.service_alerts.summary_fmt": "1 service alert",
            "stop_controller.transfer_show_earlier_departures_fmt": "Show 1 earlier departure"
        ]

        for (key, expected) in expectedSingulars {
            let format = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(String(format: format, 1) == expected, "\(key) did not resolve its singular — is Localizable.stringsdict bundled?")
        }
    }

    /// The map-type button's VoiceOver value is the one plural key here that takes a
    /// second argument, so its variable is bound positionally (`%2$#@count@`). Assert
    /// both categories: the count lands in the right slot only when that binding and the
    /// `%2$d` inside each category agree.
    ///
    /// Regression: this shipped as a flat `"%1$@, %2$d layers on"`. In a region without
    /// bikeshare the stops layer is the only one, so the singular is the *common* case
    /// and VoiceOver read "standard, 1 layers on".
    ///
    /// Deliberately locale-agnostic — English and the root plural rule agree on
    /// `one`/`other`, so this says nothing about which categories a *call site* can reach.
    /// `Polish layer count reaches its few and many forms` covers that.
    @Test func `Map type layer count reads its singular and plural`() {
        let bundle = Bundle(for: DonationCell.self)
        let format = bundle.localizedString(
            forKey: "map_controller.map_type.accessibility_value_with_layers_fmt",
            value: "MISSING",
            table: nil
        )

        #expect(String(format: format, "standard", 1) == "standard, 1 layer on")
        #expect(String(format: format, "standard", 2) == "standard, 2 layers on")
    }

    /// Which plural categories a locale can actually reach is a property of the *call site*:
    /// `String(format:)` resolves `%#@count@` against the root rule, which only defines
    /// `one` and `other`, so the `few`/`many` forms hand-written for ar, pl, and ru are dead
    /// unless the call passes a locale. English can't see the difference, which is why the
    /// English assertion above passes either way.
    ///
    /// Polish is the cheapest locale to prove it with: `few` (2–4) and `many` (5+) are
    /// different words, and neither is the `other` form. Assert through the same
    /// locale-aware path `String.localizedStringWithFormat` takes at runtime.
    ///
    /// Regression: `MapTypeButton.accessibilityValueText` shipped calling `String(format:)`,
    /// which rendered a Polish count of 5 as `other` ("5 warstwy włączonej") rather than
    /// `many` ("5 warstw włączonych").
    @Test func `Polish layer count reaches its few and many forms`() throws {
        let format = try #require(localizedFormat(
            forKey: "map_controller.map_type.accessibility_value_with_layers_fmt",
            localization: "pl"
        ))
        let polish = Locale(identifier: "pl")

        #expect(String(format: format, locale: polish, "standardowa", 1) == "standardowa, 1 warstwa włączona")
        #expect(String(format: format, locale: polish, "standardowa", 3) == "standardowa, 3 warstwy włączone")
        #expect(String(format: format, locale: polish, "standardowa", 5) == "standardowa, 5 warstw włączonych")
    }
}
