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

/// Parity checks for OBAKitWatch's strings, read from the **source tree**.
///
/// `LocalizationTests` loads each framework's bundle, which an iOS-hosted test
/// cannot do for a watchOS framework. The tables are plain plists on disk,
/// so this suite parses them relative to `#filePath` instead.
@Suite(.serialized)
struct WatchLocalizationTests {

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

    private static func strings(locale: String) -> [String: String]? {
        let url = repoRoot.appending(path: "OBAKitWatch/Strings/\(locale).lproj/Localizable.strings")
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

    @Test func `Every locale has the same keys as English`() throws {
        let english = try #require(Self.strings(locale: "en"))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale) else {
                Issue.record("OBAKitWatch/\(locale): no Localizable.strings")
                continue
            }
            let missing = Set(english.keys).subtracting(translated.keys)
            let extra = Set(translated.keys).subtracting(english.keys)
            #expect(missing.isEmpty, "OBAKitWatch/\(locale) is missing \(missing.sorted())")
            #expect(extra.isEmpty, "OBAKitWatch/\(locale) has keys not in en: \(extra.sorted())")
        }
    }

    @Test func `Every locale keeps the same format specifiers`() throws {
        let english = try #require(Self.strings(locale: "en"))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale) else { continue }
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                #expect(Self.specifiers(in: value) == Self.specifiers(in: other), "OBAKitWatch/\(locale)/\(key): specifiers differ")
            }
        }
    }

    @Test func `No locale still carries an untranslated English value`() throws {
        let english = try #require(Self.strings(locale: "en"))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale) else { continue }
            let untranslated = english.filter { key, value in translated[key] == value && value.count > 3 }.keys.sorted()
            #expect(untranslated.isEmpty, "OBAKitWatch/\(locale) still has English for \(untranslated)")
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
