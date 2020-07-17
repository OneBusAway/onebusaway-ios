//
//  FoundationExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Bundle

public extension Bundle {

    /// Returns the App Group value from the OBAKitConfig dictionary in the Info.plist. This value
    /// is used for sharing data between the main app and its extensions, like the Today View widget.
    @objc var appGroup: String? {
        guard let dict = OBAKitConfig else { return nil }
        return dict["AppGroup"] as? String
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
    var deepLinkServerBaseAddress: URL? {
        guard
            let dict = OBAKitConfig,
            let str = dict["DeepLinkServerBaseAddress"] as? String
        else { return nil }

        return URL(string: str)
    }

    /// A helper method for accessing the bundle's `ExtensionURLScheme`.
    ///
    /// `extensionURLScheme` is used as an `init()` parameter on `URLSchemeRouter`.
    var extensionURLScheme: String? {
        OBAKitConfig?["ExtensionURLScheme"] as? String
    }

    /// The name of the bundled regions JSON file, specified as `BundledRegionsFileName`.
    var bundledRegionsFileName: String? {
        return OBAKitConfig?["BundledRegionsFileName"] as? String
    }

    /// The path to the bundled regions JSON file.
    var bundledRegionsFilePath: String? {
        path(forResource: bundledRegionsFileName, ofType: nil)
    }

    /// A helper method for accessing the bundle's `RegionsServerBaseAddress`
    var regionsServerBaseAddress: URL? {
        guard
            let dict = OBAKitConfig,
            let str = dict["RegionsServerBaseAddress"] as? String
        else { return nil }

        return URL(string: str)
    }

    /// A helper method for accessing the bundle's `RegionsServerAPIPath`
    var regionsServerAPIPath: String? {
        guard
            let dict = OBAKitConfig,
            let str = dict["RegionsServerAPIPath"] as? String
        else { return nil }

        return str
    }

    /// A helper method for accessing the bundle's `OBARESTAPIKey`
    var restServerAPIKey: String? {
        guard let dict = OBAKitConfig else { return nil }
        return dict["RESTServerAPIKey"] as? String
    }

    /// A helper method for accessing the bundle's privacy policy URL
    var privacyPolicyURL: URL? {
        guard
            let dict = OBAKitConfig,
            let str = dict["PrivacyPolicyURL"] as? String
        else { return nil }

        return URL(string: str)
    }

    var appDevelopersEmailAddress: String? {
        guard let dict = OBAKitConfig else { return nil }
        return dict["AppDevelopersEmailAddress"] as? String
    }

    // MARK: - Bundle/Private

    private var OBAKitConfig: [AnyHashable: Any]? {
        optionalValue(for: "OBAKitConfig", type: [AnyHashable: Any].self)
    }

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
}

// MARK: - Dictionary

public extension Dictionary where Key == String {

    /// Creates a new `Dictionary<String, Value>` from the XML Property List at `plistPath`.
    /// - Parameter plistPath: The path to the XML Property List file.
    init?(plistPath: String) throws {
        var format = PropertyListSerialization.PropertyListFormat.xml

        guard
            let data = FileManager.default.contents(atPath: plistPath),
            let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Value]
        else { return nil }

        self = decoded
    }
}

// MARK: - HTTPURLResponse

public extension HTTPURLResponse {

    /// Returns true if this object has a Content-Type header field set with the value `application/json` or `text/json`.
    var hasJSONContentType: Bool {
        guard let contentType = contentType else {
            return false
        }

        return contentType.hasPrefix("application/json") ||
               contentType.hasPrefix("text/json")
    }

    /// Returns the value of the `Content-Type` header field.
    var contentType: String? { allHeaderFields["Content-Type"] as? String ?? nil }
}

// MARK: - MeasurementFormatter

public extension MeasurementFormatter {
    /// Converts `temperature` in the specified `unit` to `locale` without displaying a resulting unit.
    ///
    /// For example, converts 32ºF -> "0º" for Celsius locale, or 0ºC -> "32º" for Fahrenheit locale.
    /// - Parameter temperature: The temperature
    /// - Parameter unit: The unit for `temperature`
    /// - Parameter locale: The target locale
    class func unitlessConversion(temperature: Double, unit: UnitTemperature, to locale: Locale) -> String {
        let temp = Measurement(value: temperature, unit: unit)
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.numberFormatter.maximumFractionDigits = 0

        var formattedTemp = formatter.string(from: temp)

        if formattedTemp.hasSuffix("C") || formattedTemp.hasSuffix("F") {
            formattedTemp.removeLast()
        }

        return formattedTemp
    }
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

    /// Removes whitespace and newlines from `self`.
    func strip() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts empty string fields into `nil`s.
    ///
    /// There are some parts of the OneBusAway REST API that return empty strings
    /// where null would actually be a more appropriate value to provide. Alas,
    /// this will probably never change because of backwards compatibility concerns
    /// but that doesn't mean we can't address it here.
    ///
    /// - Parameter string: The string to inspect.
    /// - Returns: Nil if the string's character count is zero, and the string otherwise.
    static func nilifyBlankValue(_ string: String?) -> String? {
        guard let string = string else {
            return nil
        }

        return string.count > 0 ? string : nil
    }
}

// MARK: - String/Regex

extension String {
    /// Perform a case-insensitive match for the specified named capture groups with the specified `pattern`.
    /// - Parameters:
    ///   - pattern: The regex pattern that will be matched.
    ///   - namedGroups: The named capture groups in the regex to extract.
    public func caseInsensitiveMatch(pattern: String, namedGroups: [String]) -> [String: String]? {
        let regex = try! NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)  //swiftlint:disable:this force_try

        return match(regex: regex, namedGroups: namedGroups)
    }

    /// Perform a match for the specified named capture groups with the specified `regex`.
    /// - Parameters:
    ///   - regex: The regular expression against which the receiver will be matched.
    ///   - namedGroups: The named capture groups for which data will be extracted.
    public func match(regex: NSRegularExpression, namedGroups: [String]) -> [String: String]? {
        let range = NSRange(self.startIndex..<self.endIndex, in: self)

        guard let match = regex.firstMatch(in: self, options: [], range: range) else {
            return nil
        }

        var groupsAndValues = [String: String]()

        for component in namedGroups {
            let nsrange = match.range(withName: component)
            if nsrange.location != NSNotFound, let range = Range(nsrange, in: self) {
                groupsAndValues[component] = String(self[range])
            }
        }

        return groupsAndValues
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

// MARK: - URL

public extension URL {
    init?(phoneNumber: String) {
        self.init(string: "tel:\(phoneNumber)")
    }
}

// MARK: - URLComponents

extension URLComponents {
    /// Adds `appendedPath` to the `path` property.
    /// For example, if you have path `/api/`, calling `appendPath("foo")` will result in the `path`
    /// equaling `/api/foo`.
    /// - Parameter appendedPath: The path value to append to the receiver.
    mutating func appendPath(_ appendedPath: String) {
        if path.hasSuffix("/") && appendedPath.hasPrefix("/") {
            path = [path, appendedPath].joined(separator: "")
        }
        else {
            path = [path, appendedPath].joined(separator: "/")
        }

        path = path.replacingOccurrences(of: "//", with: "/")
    }
}

public extension URLComponents {
    /// Returns the first `URLQueryItem` with a name matching `name`.
    /// - Parameter name: The query item name to match.
    func queryItem(named name: String) -> URLQueryItem? {
        guard let queryItems = queryItems else {
            return nil
        }

        return queryItems.filter { $0.name == name }.first
    }
}

// MARK: - UUID

public extension UUID {
    init?(optionalUUIDString: String?) {
        guard let optionalUUIDString = optionalUUIDString else { return nil }
        self.init(uuidString: optionalUUIDString)
    }
}
