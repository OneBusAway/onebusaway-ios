//
//  LocalizationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

/// Guards the localization data itself, which is bulk-imported a hundred-plus keys at a
/// time and therefore drifts in ways no other test would notice: a missing key silently
/// falls back to English, and a mismatched format specifier makes `String(format:)` read
/// past its argument list.
@MainActor
class LocalizationTests: XCTestCase {

    /// Keys whose plural forms come from `Localizable.stringsdict` rather than
    /// `Localizable.strings`. Every one of these is called with `String(format:)` and a count.
    private static let pluralKeys: Set<String> = [
        "stop_page.service_alerts.summary_fmt",
        "stop_page.service_alerts.show_all_fmt",
        "stop_page.timeline.skipped_stops_fmt",
        "stop_page.past_toggle_show_a11y_fmt",
        "stop_controller.transfer_show_earlier_departures_fmt",
        "stop_page.empty.no_departures_fmt",
        "data_migration_bulletin.report_summary_number_of_failures",
        "data_migration_bulletin.report_summary_number_of_successes"
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

    private func specifiers(in value: String) -> [String] {
        let range = NSRange(value.startIndex..., in: value)
        return Self.specifier.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }

    // MARK: - Key parity

    /// A key missing from a locale silently renders in English. Nothing else catches it.
    func testEveryLocaleHasSameKeysAsEnglish() {
        for (name, bundle) in frameworks {
            guard let english = strings(in: bundle, localization: "en") else {
                return XCTFail("\(name): no en Localizable.strings")
            }
            XCTAssertGreaterThan(english.count, 100, "\(name): en table looks truncated")

            for localization in bundle.localizations where localization != "en" && localization != "Base" {
                guard let translated = strings(in: bundle, localization: localization) else { continue }
                let missing = Set(english.keys).subtracting(translated.keys)
                let extra = Set(translated.keys).subtracting(english.keys)
                XCTAssertTrue(missing.isEmpty, "\(name)/\(localization) is missing \(missing.count) key(s): \(missing.sorted().prefix(5))")
                XCTAssertTrue(extra.isEmpty, "\(name)/\(localization) has \(extra.count) key(s) not in en: \(extra.sorted().prefix(5))")
            }
        }
    }

    // MARK: - Format specifier parity

    /// A translation that drops `%@` silently renders without the app name; one that *adds*
    /// a specifier makes `String(format:)` read past the end of its arguments.
    func testEveryLocalePreservesEnglishFormatSpecifiers() {
        for (name, bundle) in frameworks {
            guard let english = strings(in: bundle, localization: "en") else { continue }

            for localization in bundle.localizations where localization != "en" && localization != "Base" {
                guard let translated = strings(in: bundle, localization: localization) else { continue }
                for (key, translation) in translated {
                    guard let source = english[key] else { continue }
                    XCTAssertEqual(
                        specifiers(in: source), specifiers(in: translation),
                        "\(name)/\(localization)/\(key): format specifiers differ from English — en=\(source) \(localization)=\(translation)"
                    )
                }
            }
        }
    }

    // MARK: - stringsdict

    /// Every locale must carry all the plural keys, with the CLDR-mandatory `other` category.
    /// A dropped entry degrades silently to the `.strings` fallback ("1 stops").
    func testEveryLocaleStringsdictIsWellFormed() {
        let bundle = Bundle(for: DonationCell.self)

        for localization in bundle.localizations where localization != "Base" {
            guard let url = bundle.url(forResource: "Localizable", withExtension: "stringsdict",
                                       subdirectory: nil, localization: localization),
                  let dict = NSDictionary(contentsOf: url) as? [String: Any]
            else {
                return XCTFail("\(localization): Localizable.stringsdict is missing or unparseable")
            }

            let missing = Self.pluralKeys.subtracting(dict.keys)
            XCTAssertTrue(missing.isEmpty, "\(localization)/stringsdict is missing \(missing.sorted())")

            for key in Self.pluralKeys {
                guard let entry = dict[key] as? [String: Any],
                      let variable = entry["count"] as? [String: Any]
                else {
                    XCTFail("\(localization)/\(key): malformed stringsdict entry")
                    continue
                }
                XCTAssertEqual(variable["NSStringFormatSpecTypeKey"] as? String, "NSStringPluralRuleType",
                               "\(localization)/\(key): wrong spec type")
                XCTAssertNotNil(variable["other"], "\(localization)/\(key): missing mandatory CLDR category 'other'")
            }
        }
    }

    /// The plural keys exist in *both* `Localizable.strings` (as the `value:` fallback) and
    /// `Localizable.stringsdict`. If the stringsdict resource ever stops being bundled, lookup
    /// silently falls back to the bare `%d` form and English renders "1 stops". Assert the
    /// singular actually resolves, which only happens when the stringsdict is present.
    func testStringsdictIsBundledSoSingularsResolve() {
        let bundle = Bundle(for: DonationCell.self)
        let expectedSingulars = [
            "stop_page.timeline.skipped_stops_fmt": "1 stop",
            "stop_page.service_alerts.summary_fmt": "1 service alert",
            "stop_controller.transfer_show_earlier_departures_fmt": "Show 1 earlier departure"
        ]

        for (key, expected) in expectedSingulars {
            let format = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            XCTAssertEqual(
                String(format: format, 1), expected,
                "\(key) did not resolve its singular — is Localizable.stringsdict bundled?"
            )
        }
    }
}
