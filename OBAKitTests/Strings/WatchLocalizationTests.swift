//
//  WatchLocalizationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing

/// Parity checks for string tables that no test can load from a bundle, read from
/// the **source tree**.
///
/// `LocalizationTests` loads each framework's bundle, which an iOS-hosted test
/// cannot do for a watchOS framework, nor for the HealthKit table, which default
/// builds leave out. The tables are plain plists on disk, so this suite parses
/// them relative to `#filePath` instead.
@Suite(.serialized)
struct WatchLocalizationTests {

    /// Each table's directory and file name.
    nonisolated private static let watchTable = "OBAKitWatch/Strings|Localizable"
    nonisolated private static let tables = [watchTable, "Apps/Shared/HealthKit/Sources|HealthKit"]

    private static let locales = ["ar", "en", "es", "fil", "fr", "it", "ko", "pl", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"]

    /// `%@`, `%d`, `%1$@`, `%2$d`, … and the escaped `%%`.
    private static let specifier = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dfs]|%%"#) // swiftlint:disable:this force_try

    private static var repoRoot: URL {
        // OBAKitTests/Strings/WatchLocalizationTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func strings(locale: String, table: String = watchTable) -> [String: String]? {
        let parts = table.split(separator: "|")
        let url = repoRoot.appending(path: "\(parts[0])/\(locale).lproj/\(parts[1]).strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private static func specifiers(in value: String) -> [String] {
        let range = NSRange(value.startIndex..., in: value)
        return specifier.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }

    @Test func `English table exists and is not empty`() throws {
        let english = try #require(Self.strings(locale: "en"))
        #expect(english.count >= 10)
    }

    @Test(arguments: tables)
    func `Every locale has the same keys as English`(table: String) throws {
        let english = try #require(Self.strings(locale: "en", table: table))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale, table: table) else {
                Issue.record("\(table)/\(locale): no strings table")
                continue
            }
            let missing = Set(english.keys).subtracting(translated.keys)
            let extra = Set(translated.keys).subtracting(english.keys)
            #expect(missing.isEmpty, "\(table)/\(locale) is missing \(missing.sorted())")
            #expect(extra.isEmpty, "\(table)/\(locale) has keys not in en: \(extra.sorted())")
        }
    }

    @Test(arguments: tables)
    func `Every locale keeps the same format specifiers`(table: String) throws {
        let english = try #require(Self.strings(locale: "en", table: table))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale, table: table) else { continue }
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                #expect(Self.specifiers(in: value) == Self.specifiers(in: other), "\(table)/\(locale)/\(key): specifiers differ")
            }
        }
    }

    @Test(arguments: tables)
    func `No locale still carries an untranslated English value`(table: String) throws {
        let english = try #require(Self.strings(locale: "en", table: table))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale, table: table) else { continue }
            let untranslated = english.filter { key, value in translated[key] == value && value.count > 3 }.keys.sorted()
            #expect(untranslated.isEmpty, "\(table)/\(locale) still has English for \(untranslated)")
        }
    }

    @Test func `The watch app's location purpose string is translated in every locale`() {
        for locale in Self.locales where locale != "en" {
            let url = Self.repoRoot.appending(path: "WatchApp/\(locale).lproj/InfoPlist.strings")
            let table = NSDictionary(contentsOf: url) as? [String: String]
            #expect(table?["NSLocationWhenInUseUsageDescription"]?.isEmpty == false, "WatchApp/\(locale): missing NSLocationWhenInUseUsageDescription")
        }
    }
}
