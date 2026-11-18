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

private struct IntentionalFallbacks: Decodable {
    let all: [String]?
    let byLocale: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case all
        case byLocale = "by_locale"
    }
}

private struct AllowedMissing: Decodable {
    let byLocale: [String: [String]]?

    enum CodingKeys: String, CodingKey {
        case byLocale = "by_locale"
    }
}

private struct FallbackAllowlist: Decodable {
    let intentionalFallbacks: IntentionalFallbacks?
    let allowedMissing: AllowedMissing?

    enum CodingKeys: String, CodingKey {
        case intentionalFallbacks = "intentional_fallbacks"
        case allowedMissing = "allowed_missing"
    }
}

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

    private static func loadAllowlist() throws -> FallbackAllowlist {
        let url = repoRoot.appending(path: "OBAKitWatch/Strings/fallback_allowlist.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FallbackAllowlist.self, from: data)
    }

    private static var allowlist: FallbackAllowlist {
        get throws {
            try loadAllowlist()
        }
    }

    private static func isIntentionalFallback(key: String, locale: String, allowlist: FallbackAllowlist) -> Bool {
        let fallbacks = allowlist.intentionalFallbacks
        if let all = fallbacks?.all, all.contains(key) { return true }
        if let byLocale = fallbacks?.byLocale?[locale], byLocale.contains(key) { return true }
        return false
    }

    private static func isAllowedMissing(key: String, locale: String, allowlist: FallbackAllowlist) -> Bool {
        guard let byLocale = allowlist.allowedMissing?.byLocale?[locale] else { return false }
        return byLocale.contains(key)
    }

    private static func isIntentionalFallback(key: String, locale: String) -> Bool {
        guard let allowlist = try? loadAllowlist() else { return false }
        return isIntentionalFallback(key: key, locale: locale, allowlist: allowlist)
    }

    private static func isAllowedMissing(key: String, locale: String) -> Bool {
        guard let allowlist = try? loadAllowlist() else { return false }
        return isAllowedMissing(key: key, locale: locale, allowlist: allowlist)
    }

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

    private static var allEnglishKeys: Set<String> {
        var keys = Set<String>()
        for table in tables {
            if let dict = strings(locale: "en", table: table) {
                keys.formUnion(dict.keys)
            }
        }
        return keys
    }

    private static func specifiers(in value: String) -> [String] {
        let range = NSRange(value.startIndex..., in: value)
        var implicitIndex = 1
        var result: [String] = []
        for match in specifier.matches(in: value, range: range) {
            guard let r = Range(match.range, in: value) else { continue }
            let token = String(value[r])
            if token == "%%" {
                result.append("%%")
            } else if token.contains("$") {
                result.append(token)
            } else {
                let type = token.dropFirst()
                result.append("%\(implicitIndex)$\(type)")
                implicitIndex += 1
            }
        }
        return result.sorted()
    }

    @Test func `English table exists and is not empty`() throws {
        let english = try #require(Self.strings(locale: "en"))
        #expect(english.count >= 10)
    }

    @Test(arguments: tables)
    func `Every locale has the same keys as English`(table: String) throws {
        let parts = table.split(separator: "|")
        let enRelativePath = "\(parts[0])/en.lproj/\(parts[1]).strings"
        let english = try #require(Self.strings(locale: "en", table: table), "File: \(enRelativePath): Missing English strings table")
        try #require(!english.isEmpty, "File: \(enRelativePath): Base English table is empty")
        let allowlist = try Self.loadAllowlist()

        for locale in Self.locales where locale != "en" {
            let relativePath = "\(parts[0])/\(locale).lproj/\(parts[1]).strings"
            guard let translated = Self.strings(locale: locale, table: table) else {
                Issue.record("File: \(relativePath), Locale: \(locale): Missing strings table")
                continue
            }
            let missing = Set(english.keys)
                .subtracting(translated.keys)
                .filter { !Self.isAllowedMissing(key: $0, locale: locale, allowlist: allowlist) }
            for key in missing.sorted() {
                Issue.record("File: \(relativePath), Locale: \(locale), Key: '\(key)': Missing key from English base table")
            }
            let extra = Set(translated.keys).subtracting(english.keys)
            for key in extra.sorted() {
                Issue.record("File: \(relativePath), Locale: \(locale), Key: '\(key)': Extra key not in English base table")
            }
        }
    }

    @Test(arguments: tables)
    func `Every locale keeps the same format specifiers`(table: String) throws {
        let parts = table.split(separator: "|")
        let enRelativePath = "\(parts[0])/en.lproj/\(parts[1]).strings"
        let english = try #require(Self.strings(locale: "en", table: table), "File: \(enRelativePath): Missing English strings table")
        try #require(!english.isEmpty, "File: \(enRelativePath): Base English table is empty")

        for locale in Self.locales where locale != "en" {
            let relativePath = "\(parts[0])/\(locale).lproj/\(parts[1]).strings"
            guard let translated = Self.strings(locale: locale, table: table) else { continue }
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                let expected = Self.specifiers(in: value)
                let actual = Self.specifiers(in: other)
                if expected != actual {
                    Issue.record("File: \(relativePath), Locale: \(locale), Key: '\(key)': Format arguments differ (expected: \(expected), got: \(actual))")
                }
            }
        }
    }

    @Test(arguments: tables)
    func `No locale still carries an untranslated English value`(table: String) throws {
        let parts = table.split(separator: "|")
        let enRelativePath = "\(parts[0])/en.lproj/\(parts[1]).strings"
        let english = try #require(Self.strings(locale: "en", table: table), "File: \(enRelativePath): Missing English strings table")
        try #require(!english.isEmpty, "File: \(enRelativePath): Base English table is empty")
        let allowlist = try Self.loadAllowlist()

        for locale in Self.locales where locale != "en" {
            let relativePath = "\(parts[0])/\(locale).lproj/\(parts[1]).strings"
            guard let translated = Self.strings(locale: locale, table: table) else { continue }
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                if other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Self.isIntentionalFallback(key: key, locale: locale, allowlist: allowlist) {
                    Issue.record("File: \(relativePath), Locale: \(locale), Key: '\(key)': Empty or whitespace-only translation value without intentional fallback allowlist entry")
                } else if value.count > 3 && other == value && !Self.isIntentionalFallback(key: key, locale: locale, allowlist: allowlist) {
                    Issue.record("File: \(relativePath), Locale: \(locale), Key: '\(key)': Untranslated English value without intentional fallback allowlist entry")
                }
            }
        }
    }

    @Test func `Fallback allowlist keys are valid in English tables`() throws {
        let allowlist = try Self.loadAllowlist()
        let allKeys = Self.allEnglishKeys
        #expect(!allKeys.isEmpty, "English base tables must not be empty")

        if let all = allowlist.intentionalFallbacks?.all {
            for key in all {
                #expect(allKeys.contains(key), "File: OBAKitWatch/Strings/fallback_allowlist.json: Key '\(key)' does not exist in English base tables")
            }
        }
        if let byLocale = allowlist.intentionalFallbacks?.byLocale {
            for (locale, keys) in byLocale {
                #expect(Self.locales.contains(locale), "File: OBAKitWatch/Strings/fallback_allowlist.json: Unknown locale '\(locale)' in intentional_fallbacks")
                for key in keys {
                    #expect(allKeys.contains(key), "File: OBAKitWatch/Strings/fallback_allowlist.json, Locale: \(locale): Key '\(key)' does not exist in English base tables")
                }
            }
        }
        if let allowedMissing = allowlist.allowedMissing?.byLocale {
            for (locale, keys) in allowedMissing {
                #expect(Self.locales.contains(locale), "File: OBAKitWatch/Strings/fallback_allowlist.json: Unknown locale '\(locale)' in allowed_missing")
                for key in keys {
                    #expect(allKeys.contains(key), "File: OBAKitWatch/Strings/fallback_allowlist.json, Locale: \(locale): Key '\(key)' does not exist in English base tables")
                }
            }
        }
    }

    @Test func `The watch app's location purpose string is translated in every locale`() {
        for locale in Self.locales where locale != "en" {
            let relativePath = "WatchApp/\(locale).lproj/InfoPlist.strings"
            let url = Self.repoRoot.appending(path: relativePath)
            let table = NSDictionary(contentsOf: url) as? [String: String]
            let purpose = table?["NSLocationWhenInUseUsageDescription"]
            #expect(purpose?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "WatchApp/\(locale): missing NSLocationWhenInUseUsageDescription")
        }
    }
}
