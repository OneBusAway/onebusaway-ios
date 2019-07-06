//
//  UserDataStore.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/18/19.
//

import Foundation
import CocoaLumberjackSwift

@objc(OBASelectedTab) public enum SelectedTab: Int {
    case map, recentStops, bookmarks, settings
}

/// `UserDataStore` is a repository for the user's data, such as bookmarks, and recent stops.
///
/// This protocol is designed to support pluggable data storage layers, so that services ranging
/// from UserDefaults, CloudKit, Firebase, or custom persistence systems (local or remote)
/// could be used to store a user's data.
@objc(OBAUserDataStore)
public protocol UserDataStore: NSObjectProtocol {

    // MARK: - Debug Mode

    var debugMode: Bool { get set }

    // MARK: - Bookmark Groups

    /// Retrieves a list of `BookmarkGroup` objects.
    var bookmarkGroups: [BookmarkGroup] { get }

    /// Adds a new `BookmarkGroup` to the `UserDataStore`
    /// - Parameter bookmarkGroup: The `BookmarkGroup` to add.
    func add(bookmarkGroup: BookmarkGroup)

    /// Removes the `BookmarkGroup` from the `UserDataStore`.
    /// - Parameter bookmarkGroup: The `BookmarkGroup` to remove.
    ///
    /// - Note: `Bookmark`s should not be deleted when their `BookmarkGroup` is deleted.
    func delete(bookmarkGroup: BookmarkGroup)

    /// Finds the `BookmarkGroup` with a matching `uuid` if it exists.
    /// - Parameter uuid: The `UUID` for which to search in existing bookmark groups.
    func findGroup(uuid: UUID) -> BookmarkGroup?

    // MARK: - Bookmarks

    /// Retrieves a list of `Bookmark` objects.
    var bookmarks: [Bookmark] { get }

    /// Returns a list of `Bookmark`s in the specified `BookmarkGroup`
    /// - Parameter bookmarkGroup: The `BookmarkGroup` for which `Bookmark`s should be returned.
    func bookmarksInGroup(_ bookmarkGroup: BookmarkGroup?) -> [Bookmark]

    /// Adds the specified `Bookmark` to the `UserDataStore`, optionally adding it to a `BookmarkGroup`.
    /// - Parameter bookmark: The `Bookmark` to add to the store.
    /// - Parameter group: Optional. The `BookmarkGroup` to which this `Bookmark` will belong.
    func add(_ bookmark: Bookmark, to group: BookmarkGroup?)

    /// Deletes the specified `Bookmark` from the `UserDataStore`.
    /// - Parameter bookmark: The `Bookmark` to delete.
    /// - Returns: The index of the bookmark, if found. Otherwise returns `NSNotFound`.
    func delete(bookmark: Bookmark) -> Int

    /// Finds the `Bookmark` with a matching `uuid` if it exists.
    /// - Parameter uuid: The `UUID` for which to search in existing bookmarks.
    func findBookmark(uuid: UUID) -> Bookmark?

    /// Finds the `Bookmark` with a matching `stopID` if it exists.
    /// - Parameter stopID: The Stop ID for which to search in existing bookmarks.
    func findBookmark(stopID: String) -> Bookmark?

    // MARK: - Recent Stops

    /// A list of recently-viewed stops
    var recentStops: [Stop] { get }

    /// Add a `Stop` to the list of recently-viewed `Stop`s
    ///
    /// - Parameter stop: The stop to add to the list
    /// - Parameter region: The `Region` in which this `Stop` resides.
    func addRecentStop(_ stop: Stop, region: Region)

    /// Deletes all recent stops.
    func deleteAllRecentStops()

    /// Deletes the specified Stop from the list of recent stops.
    /// - Parameter recentStop: The stop to delete.
    func delete(recentStop: Stop)

    /// The maximum number of recent stops that will be stored.
    var maximumRecentStopsCount: Int { get }

    // MARK: - View State/Last Selected Tab

    /// Stores the last selected tab that the user viewed.
    ///
    /// - Note: Only applies if the user is using a tab-style UI.
    var lastSelectedView: SelectedTab { get set }
}

// MARK: - UserDefaultsStore

@objc(OBAUserDefaultsStore)
public class UserDefaultsStore: NSObject, UserDataStore {

    let userDefaults: UserDefaults

    enum UserDefaultsKeys: String {
        case debugMode
        case bookmarks
        case bookmarkGroups
        case recentStops
        case lastSelectedView
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults

        self.userDefaults.register(defaults: [UserDefaultsKeys.debugMode.rawValue: false])
    }

    // MARK: - Debug Mode

    public var debugMode: Bool {
        get {
            return userDefaults.bool(forKey: UserDefaultsKeys.debugMode.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.debugMode.rawValue)
        }
    }

    // MARK: - Bookmark Groups

    public var bookmarkGroups: [BookmarkGroup] {
        get {
            return decodeUserDefaultsObjects(type: BookmarkGroup.self, key: .bookmarkGroups)
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: .bookmarkGroups) // swiftlint:disable:this force_try
        }
    }

    public func add(bookmarkGroup: BookmarkGroup) {
        guard bookmarkGroups.firstIndex(of: bookmarkGroup) == nil else { return }
        bookmarkGroups.append(bookmarkGroup)
    }

    public func delete(bookmarkGroup: BookmarkGroup) {
        if let index = bookmarkGroups.firstIndex(of: bookmarkGroup) {
            bookmarkGroups.remove(at: index)
        }
    }

    public func findGroup(uuid: UUID) -> BookmarkGroup? {
        bookmarkGroups.first { $0.uuid == uuid }
    }

    // MARK: - Bookmarks

    public var bookmarks: [Bookmark] {
        get {
            return decodeUserDefaultsObjects(type: Bookmark.self, key: .bookmarks)
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: .bookmarks) // swiftlint:disable:this force_try
        }
    }

    public func bookmarksInGroup(_ bookmarkGroup: BookmarkGroup?) -> [Bookmark] {
        let uuid = bookmarkGroup?.uuid ?? nil
        return bookmarks.filter { $0.groupUUID == uuid }
    }

    public func add(_ bookmark: Bookmark, to group: BookmarkGroup? = nil) {
        if let group = group {
            add(bookmarkGroup: group)
        }

        bookmark.groupUUID = group?.uuid ?? nil

        var insertionIndex = NSNotFound

        if let existing = findBookmark(uuid: bookmark.uuid) {
            insertionIndex = delete(bookmark: existing)
        }

        if insertionIndex == NSNotFound {
            bookmarks.append(bookmark)
        }
        else {
            bookmarks.insert(bookmark, at: insertionIndex)
        }
    }

    @discardableResult public func delete(bookmark: Bookmark) -> Int {
        let bookmark = findBookmark(uuid: bookmark.uuid, defaultValue: bookmark)
        guard let index = bookmarks.firstIndex(of: bookmark) else { return NSNotFound }

        bookmarks.remove(at: index)
        return index
    }

    /// Finds the specified `Bookmark` by UUID or returns the `defaultValue`. Useful for upserts and the like.
    /// - Parameter uuid: The `UUID` value of the `Bookmark` you want to find.
    /// - Parameter defaultValue: A `Bookmark` to replace if a match is not found for `uuid`.
    func findBookmark(uuid: UUID, defaultValue: Bookmark) -> Bookmark {
        findBookmark(uuid: uuid) ?? defaultValue
    }

    /// Finds the `Bookmark` with a matching `uuid` if it exists.
    /// - Parameter uuid: The `UUID` for which to search in existing bookmarks.
    public func findBookmark(uuid: UUID) -> Bookmark? {
        bookmarks.first { $0.uuid == uuid }
    }

    public func findBookmark(stopID: String) -> Bookmark? {
        bookmarks.first { $0.stopID == stopID }
    }

    private func updateBookmarksWithStop(_ stop: Stop, region: Region) {
        let matchingBookmarks = bookmarks.filter { $0.stopID == stop.id && $0.regionIdentifier == region.regionIdentifier}
        for bookmark in matchingBookmarks {
            bookmark.stop = stop
            upsert(bookmark: bookmark)
        }
    }

    // MARK: - Recent Stops

    public var recentStops: [Stop] {
        get {
            return decodeUserDefaultsObjects(type: Stop.self, key: .recentStops)
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: .recentStops) // swiftlint:disable:this force_try
        }
    }

    public func addRecentStop(_ stop: Stop, region: Region) {
        var recentStops = self.recentStops

        updateBookmarksWithStop(stop, region: region)

        if let idx = recentStops.firstIndex(of: stop) {
            recentStops.remove(at: idx)
        }
        recentStops.insert(stop, at: 0)

        if recentStops.count > maximumRecentStopsCount {
            self.recentStops = Array(recentStops[0..<maximumRecentStopsCount])
        }
        else {
            self.recentStops = recentStops
        }
    }

    public func deleteAllRecentStops() {
        recentStops.removeAll()
    }

    public func delete(recentStop: Stop) {
        if let idx = recentStops.firstIndex(of: recentStop) {
            recentStops.remove(at: idx)
        }
    }

    public var maximumRecentStopsCount: Int {
        return 20
    }

    // MARK: - View State/Last Selected Tab

    public var lastSelectedView: SelectedTab {
        get {
            guard userDefaults.contains(key: UserDefaultsKeys.lastSelectedView.rawValue) else {
                return .map
            }
            let raw = userDefaults.integer(forKey: UserDefaultsKeys.lastSelectedView.rawValue)
            return SelectedTab(rawValue: raw)!
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: UserDefaultsKeys.lastSelectedView.rawValue)
        }
    }

    // MARK: - Private Helpers

    private func upsert(bookmark: Bookmark) {
        if
            let existing = findBookmark(uuid: bookmark.uuid),
            let index = bookmarks.firstIndex(of: existing)
        {
            bookmarks.remove(at: index)
            bookmarks.insert(bookmark, at: index)
        }
        else {
            bookmarks.append(bookmark)
        }
    }

    /// Decodes arrays of `Decodable` objects stored in user defaults.
    ///
    /// - Parameter type: the type of the object to be decoded. For example, `Bookmark.self` or `Stop.self`.
    /// - Parameter key: The user defaults key that corresponds to the data type.
    /// - Returns: An array of objects of type `T`.
    ///
    /// - Note: If an error is encountered while decoding the array, a message will be printed to the console and an empty array returned.
    private func decodeUserDefaultsObjects<T>(type: T.Type, key: UserDefaultsKeys) -> [T] where T: Decodable {
        do {
            let obj = try userDefaults.decodeUserDefaultsObjects(type: [T].self, key: key.rawValue)
            return obj ?? []
        }
        catch let error {
            DDLogError("Unable to decode \(key.rawValue): \(error)")
            return []
        }
    }

    /// Encodes an array of `Encodable` objects and stores them in user defaults.
    /// - Parameter objects: An array of `Encodable` objects. For example, bookmarks.
    /// - Parameter key: The user defaults key that corresponds to the data being saved.
    private func encodeUserDefaultsObjects<T>(_ objects: [T], key: UserDefaultsKeys) throws where T: Encodable {
        try userDefaults.encodeUserDefaultsObjects(objects, key: key.rawValue)
    }
}
