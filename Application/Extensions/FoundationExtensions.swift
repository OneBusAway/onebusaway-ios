//
//  FoundationExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/22/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation

// MARK: - Bundle

public extension Bundle {

    private func url(for key: String) -> URL? {
        guard let address = optionalValue(for: key, type: String.self) else { return nil }
        return URL(string: address)
    }

    private func value<T>(for key: String, type: T.Type) -> T {
        optionalValue(for: key, type: type)!
    }

    private func optionalValue<T>(for key: String, type: T.Type) -> T? {
        object(forInfoDictionaryKey: key) as? T
    }

    /// The display name of the app. e.g. "OneBusAway".
    var appName: String { value(for: "CFBundleDisplayName", type: String.self) }

    /// The copyright string for the app. e.g. "© Open Transit Software Foundation".
    var copyright: String { value(for: "NSHumanReadableCopyright", type: String.self) }

    /// The app's version number. e.g. "19.1.0".
    var appVersion: String { value(for: "CFBundleShortVersionString", type: String.self) }

    /// A helper method for easily accessing the bundle's `CFBundleIdentifier`.
    var bundleIdentifier: String { value(for: "CFBundleIdentifier", type: String.self) }

    /// A helper method for easily accessing the bundle's `NSUserActivityTypes`.
    var userActivityTypes: [String]? { optionalValue(for: "NSUserActivityTypes", type: [String].self) }

    /// A helper method for accessing the bundle's `DeepLinkServerBaseAddress`
    var deepLinkServerBaseAddress: URL? { url(for: "DeepLinkServerBaseAddress") }

    /// A helper method for accessing the bundle's privacy policy URL
    var privacyPolicyURL: URL? { url(for: "PrivacyPolicyURL") }

    var appDevelopersEmailAddress: String? { optionalValue(for: "AppDevelopersEmailAddress", type: String.self) }
}

// MARK: - Sequence

public extension Sequence where Element == String {

    /// Performs a localized case insensitive sort on the receiver.
    ///
    /// - Returns: A localized, case-insensitive sorted Array.
    func localizedCaseInsensitiveSort() -> [Element] {
        return sorted { (s1, s2) -> Bool in
            return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
        }
    }
}

// MARK: - String

// From https://stackoverflow.com/a/55619708/136839
public extension String {

    /// true if the string consists of the characters 0-9 exclusively, and false otherwise.
    var isNumeric: Bool {
        guard self.count > 0 else { return false }
        let nums: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        return Set(self).isSubset(of: nums)
    }
}

// MARK: - User Defaults

public extension UserDefaults {

    enum UserDefaultsError: Error {
        case typeMismatch
    }

    /// Returns a typed object for `key`, if it exists.
    ///
    /// - Parameters:
    ///   - type: The type of the object to return.
    ///   - key: The key for the object.
    /// - Returns: The object, if it exists in the user defaults. Otherwise `nil`.
    /// - Throws: `UserDefaultsError.typeMismatch` if you passed in the wrong type `T`.
    func object<T>(type: T.Type, forKey key: String) throws -> T? {
        guard let obj = object(forKey: key) else {
            return nil
        }

        if let typedObj = obj as? T {
            return typedObj
        }
        else {
            throw UserDefaultsError.typeMismatch
        }
    }

    /// A simple way to check if this object contains a value for `key`.
    ///
    /// - Parameter key: The key to check if a value exists for.
    /// - Returns: `true` if the value exists, and `false` if it does not.
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }

    /// Decodes arrays of `Decodable` objects stored in user defaults.
    ///
    /// - Parameter type: the type of the object to be decoded. For example, `Bookmark.self` or `[Bookmark].self`.
    /// - Parameter key: The user defaults key that corresponds to the data type.
    /// - Returns: An object of type `T`.
    ///
    /// - throws: An error if any value throws an error during decoding.
    func decodeUserDefaultsObjects<T>(type: T.Type, key: String) throws -> T? where T: Decodable {
        guard let data = try object(type: Data.self, forKey: key) else {
            return nil
        }

        return try PropertyListDecoder().decode(T.self, from: data)
    }

    /// Encodes an `Encodable` object and stores it in user defaults.
    /// - Parameter object: An `Encodable` object. For example, a `Bookmark` or `[Bookmark]`.
    /// - Parameter key: The user defaults key that corresponds to the data being saved.
    func encodeUserDefaultsObjects<T>(_ object: T, key: String) throws where T: Encodable {
        let encoded = try PropertyListEncoder().encode(object)
        set(encoded, forKey: key)
    }
}
