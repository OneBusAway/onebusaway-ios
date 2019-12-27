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

    /// Adds the `BookmarkGroup` to the `UserDataStore`, or updates it if it's new.
    /// - Parameter bookmarkGroup: The `BookmarkGroup` to add.
    func upsert(bookmarkGroup: BookmarkGroup)

    /// Removes the specified `BookmarkGroup` from the `UserDataStore`.
    /// - Parameter group: The `BookmarkGroup` to remove.
    ///
    /// - Note: `Bookmark`s should not be deleted when their `BookmarkGroup` is deleted.
    func deleteGroup(_ group: BookmarkGroup)

    /// Removes the `BookmarkGroup` that matches `id` from the `UserDataStore`.
    /// - Parameter id: The `UUID` of the `BookmarkGroup` to remove.
    ///
    /// - Note: `Bookmark`s should not be deleted when their `BookmarkGroup` is deleted.
    func deleteGroup(id: UUID)

    /// Finds the `BookmarkGroup` with a matching `id` if it exists.
    /// - Parameter id: The `UUID` for which to search in existing bookmark groups.
    func findGroup(id: UUID?) -> BookmarkGroup?

    /// Updates, inserts, and deletes existing bookmark groups with the supplied list.
    /// - Parameter newGroups: The new, canonical list of `BookmarkGroup`s.
    func replaceBookmarkGroups(with newGroups: [BookmarkGroup])

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

    /// Finds the `Bookmark` with a matching `id` if it exists.
    /// - Parameter id: The `UUID` for which to search in existing bookmarks.
    func findBookmark(id: UUID) -> Bookmark?

    /// Finds the `Bookmark` with a matching `stopID` if it exists.
    /// - Parameter stopID: The Stop ID for which to search in existing bookmarks.
    func findBookmark(stopID: String) -> Bookmark?

    /// Finds `Bookmark`s that match the provided search text.
    /// - Parameter searchText: The text to search `Bookmark`s for.
    func findBookmarks(matching searchText: String) -> [Bookmark]

    // MARK: - Recent Stops

    /// Find recent stops that match `searchText`
    /// - Parameter searchText: The search string
    func findRecentStops(matching searchText: String) -> [Stop]

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

// MARK: - Stop Preferences

public protocol StopPreferencesStore: NSObjectProtocol {
    /// Updates the Stop Preferences (sorting/filtering) for the specified Stop.
    /// - Parameter stopPreferences: The sorting and filtering options for the `Stop`.
    /// - Parameter stop: The `Stop` to which the `stopPreferences` will be applied.
    /// - Parameter region: The `Region` in which `stop` exists.
    func set(stopPreferences: StopPreferences, stop: Stop, region: Region)

    /// Retrieves the `stopPreferences` for the specified `Stop`. Always returns a value.
    /// - Parameter stopID: The ID of the `Stop` for which `StopPreferences` will be retrieved.
    /// - Parameter region: The `Region` in which `stop` exists.
    func preferences(stopID: String, region: Region) -> StopPreferences
}

// MARK: - UserDefaultsStore

@objc(OBAUserDefaultsStore)
public class UserDefaultsStore: NSObject, UserDataStore, StopPreferencesStore {

    let userDefaults: UserDefaults

    enum UserDefaultsKeys: String {
        case debugMode
        case bookmarks
        case bookmarkGroups
        case recentStops
        case stopPreferences
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
            let groups: [BookmarkGroup] = decodeUserDefaultsObjects(type: [BookmarkGroup].self, key: .bookmarkGroups) ?? []
            return groups.sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: .bookmarkGroups) // swiftlint:disable:this force_try
        }
    }

    public func upsert(bookmarkGroup: BookmarkGroup) {
        if let index = findGroupIndex(id: bookmarkGroup.id) {
            bookmarkGroups.remove(at: index)
            bookmarkGroups.insert(bookmarkGroup, at: index)
        }
        else {
            bookmarkGroups.append(bookmarkGroup)
        }
    }

    public func deleteGroup(_ group: BookmarkGroup) {
        // move the group's bookmarks, if any, out of the group.
        for bm in bookmarksInGroup(group) {
            add(bm, to: nil)
        }

        if let index = findGroupIndex(id: group.id) {
            bookmarkGroups.remove(at: index)
        }
    }

    public func deleteGroup(id: UUID) {
        if let group = findGroup(id: id) {
            deleteGroup(group)
        }
    }

    public func findGroup(id: UUID?) -> BookmarkGroup? {
        guard let id = id else {
            return nil
        }

        return bookmarkGroups.first { $0.id == id }
    }

    public func findGroupIndex(id: UUID) -> Int? {
        bookmarkGroups.firstIndex { $0.id == id }
    }

    public func replaceBookmarkGroups(with newGroups: [BookmarkGroup]) {
        // All registered groups
        var groupsToDelete = Set(bookmarkGroups.map { $0.id })

        // Remove items from the set that still exist.
        for g in newGroups {
            groupsToDelete.remove(g.id)
        }

        // Delete the remaining items (which definitionally are items the user has deleted).
        for uuid in groupsToDelete {
            deleteGroup(id: uuid)
        }

        // Update/insert the new list of groups.
        for g in newGroups {
            upsert(bookmarkGroup: g)
        }
    }

    // MARK: - Bookmarks

    public var bookmarks: [Bookmark] {
        get {
            return decodeUserDefaultsObjects(type: [Bookmark].self, key: .bookmarks) ?? []
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: .bookmarks) // swiftlint:disable:this force_try
        }
    }

    public func bookmarksInGroup(_ bookmarkGroup: BookmarkGroup?) -> [Bookmark] {
        let id = bookmarkGroup?.id ?? nil
        return bookmarks.filter { $0.groupID == id }
    }

    public func add(_ bookmark: Bookmark, to group: BookmarkGroup? = nil) {
        if let group = group {
            upsert(bookmarkGroup: group)
        }

        bookmark.groupID = group?.id ?? nil

        var insertionIndex = NSNotFound

        if let existing = findBookmark(id: bookmark.id) {
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
        let bookmark = findBookmark(id: bookmark.id, defaultValue: bookmark)
        guard let index = bookmarks.firstIndex(of: bookmark) else { return NSNotFound }

        bookmarks.remove(at: index)
        return index
    }

    /// Finds the specified `Bookmark` by `id` or returns the `defaultValue`. Useful for upserts and the like.
    /// - Parameter id: The unique identifier of the `Bookmark` you want to find.
    /// - Parameter defaultValue: A `Bookmark` to replace if a match is not found for `id`.
    func findBookmark(id: UUID, defaultValue: Bookmark) -> Bookmark {
        findBookmark(id: id) ?? defaultValue
    }

    /// Finds the `Bookmark` with a matching `id` if it exists.
    /// - Parameter id: The unique identifier for which to search in existing bookmarks.
    public func findBookmark(id: UUID) -> Bookmark? {
        bookmarks.first { $0.id == id }
    }

    public func findBookmark(stopID: String) -> Bookmark? {
        bookmarks.first { $0.stopID == stopID }
    }

    public func findBookmarks(matching searchText: String) -> [Bookmark] {
        let cleanedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return bookmarks.filter { $0.matchesQuery(cleanedText) }
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
            return decodeUserDefaultsObjects(type: [Stop].self, key: .recentStops) ?? []
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

    public func findRecentStops(matching searchText: String) -> [Stop] {
        let cleanedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return recentStops.filter { $0.matchesQuery(cleanedText) }
    }

    // MARK: - Stop Preferences

    public func set(stopPreferences: StopPreferences, stop: Stop, region: Region) {
        let key = stopPreferencesKey(id: stop.id, region: region)
        self.stopPreferences[key] = stopPreferences
    }

    public func preferences(stopID: String, region: Region) -> StopPreferences {
        let prefs = stopPreferences
        let key = stopPreferencesKey(id: stopID, region: region)
        return prefs[key] ?? StopPreferences()
    }

    private func stopPreferencesKey(id: String, region: Region) -> String {
        "\(region.regionIdentifier)_\(id)"
    }

    private var stopPreferences: [String: StopPreferences] {
        get {
            return decodeUserDefaultsObjects(type: [String: StopPreferences].self, key: .stopPreferences) ?? [:]
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: .stopPreferences) // swiftlint:disable:this force_try
        }
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
            let existing = findBookmark(id: bookmark.id),
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
    private func decodeUserDefaultsObjects<T>(type: T.Type, key: UserDefaultsKeys) -> T? where T: Decodable {
        do {
            let obj = try userDefaults.decodeUserDefaultsObjects(type: T.self, key: key.rawValue)
            return obj
        }
        catch let error {
            DDLogError("Unable to decode \(key.rawValue): \(error)")
            return nil
        }
    }

    /// Encodes an array of `Encodable` objects and stores them in user defaults.
    /// - Parameter objects: An `Encodable` object (or an array of them). For example, bookmarks.
    /// - Parameter key: The user defaults key that corresponds to the data being saved.
    private func encodeUserDefaultsObjects<T>(_ object: T, key: UserDefaultsKeys) throws where T: Encodable {
        try userDefaults.encodeUserDefaultsObjects(object, key: key.rawValue)
    }
}
