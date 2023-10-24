//
//  UserDataStore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

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

    /// Retrieves `Bookmark`s where `isFavorite == true`.
    var favoritedBookmarks: [Bookmark] { get }

    /// Returns a list of `Bookmark`s in the specified `BookmarkGroup`
    /// - Parameter bookmarkGroup: The `BookmarkGroup` for which `Bookmark`s should be returned.
    func bookmarksInGroup(_ bookmarkGroup: BookmarkGroup?) -> [Bookmark]

    /// Adds the specified `Bookmark` to the `UserDataStore`, optionally adding it to a `BookmarkGroup`.
    /// - Parameters:
    ///   - bookmark: The `Bookmark` to add to the store.
    ///   - group: Optional. The `BookmarkGroup` to which this `Bookmark` will belong.
    func add(_ bookmark: Bookmark, to group: BookmarkGroup?)

    /// Adds the specified `Bookmark` to the `UserDataStore`, optionally adding it to a `BookmarkGroup` at `index`.
    /// - Parameters:
    ///   - bookmark: The `Bookmark` to add to the store.
    ///   - group: Optional. The `BookmarkGroup` to which this `Bookmark` will belong.
    ///   - index: The sort order or index of the bookmark in its group. Pass in `Int.max` to append to the end.
    func add(_ bookmark: Bookmark, to group: BookmarkGroup?, index: Int)

    /// Deletes the specified `Bookmark` from the `UserDataStore`.
    /// - Parameter bookmark: The `Bookmark` to delete.
    func delete(bookmark: Bookmark)

    /// Finds the `Bookmark` with a matching `id` if it exists.
    /// - Parameter id: The `UUID` for which to search in existing bookmarks.
    func findBookmark(id: UUID) -> Bookmark?

    /// Finds the `Bookmark` with a matching `stopID` if it exists.
    /// - Parameter stopID: The Stop ID for which to search in existing bookmarks.
    func findBookmark(stopID: StopID) -> Bookmark?

    /// Finds `Bookmark`s that match the provided search text.
    /// - Parameter searchText: The text to search `Bookmark`s for.
    func findBookmarks(matching searchText: String) -> [Bookmark]

    /// Finds `Bookmark`s in the specified `Region`.
    /// - Parameter region: The region of the `Bookmark`s.
    func findBookmarks(in region: Region?) -> [Bookmark]

    /// Examines the list of bookmarks to see if a `Bookmark` exists whose contents match `bookmark`
    /// by using the method `Bookmark.isEqualish()` to determine if a match exists.
    /// - Parameter bookmark: The bookmark that will compared to the current list of bookmarks.
    func checkForDuplicates(bookmark: Bookmark) -> Bool

    // MARK: - Recent Stops

    /// Find recent stops that match `searchText`
    /// - Parameter searchText: The search string
//    func findRecentStops(matching searchText: String) -> [Stop]
//
//    /// A list of recently-viewed stops
//    var recentStops: [Stop] { get }
//
//    /// Add a `Stop` to the list of recently-viewed `Stop`s
//    ///
//    /// - Parameter stop: The stop to add to the list
//    /// - Parameter region: The `Region` in which this `Stop` resides.
//    func addRecentStop(_ stop: Stop, region: Region)
//
//    /// Deletes all recent stops.
//    func deleteAllRecentStops()
//
//    /// Deletes the specified Stop from the list of recent stops.
//    /// - Parameter recentStop: The stop to delete.
//    func delete(recentStop: Stop)
//
//    /// The maximum number of recent stops that will be stored.
//    var maximumRecentStopsCount: Int { get }

    // MARK: - Alarms

    /// Deletes (but does not deregister) all `Alarm`s that have arrived/departed.
    func deleteExpiredAlarms()

    /// All currently-known and registered `Alarm`s.
    var alarms: [Alarm] { get }

    /// Store a new alarm.
    /// - Note: Calling this method does not register your `Alarm`.
    /// - Parameter alarm: The alarm object to store.
    func add(alarm: Alarm)

    /// Delete an alarm.
    /// - Note: Calling this method does not deregister your `Alarm`.
    /// - Parameter alarm: The alarm object to delete.
    func delete(alarm: Alarm)

    // MARK: - View State/Last Selected Tab

    /// Stores the last selected tab that the user viewed.
    ///
    /// - Note: Only applies if the user is using a tab-style UI.
    var lastSelectedView: SelectedTab { get set }

    // MARK: - Service Alerts

    /// Lets you check whether the passed-in service has been viewed by the user or not.
    /// - Parameter serviceAlert: The service alert to check the read status of.
    func isUnread(serviceAlert: ServiceAlert) -> Bool

    /// Lets you mark a service alert as having been read.
    /// - Parameter serviceAlert: The service alert to mark read.
    func markRead(serviceAlert: ServiceAlert)
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
    func preferences(stopID: StopID, region: Region) -> StopPreferences
}

// MARK: - UserDefaultsStore

@objc(OBAUserDefaultsStore)
public class UserDefaultsStore: NSObject, UserDataStore, StopPreferencesStore {

    let userDefaults: UserDefaults

    private struct UserDefaultsKeys {
        static let alarms = "UserDataStore.alarms"
        static let bookmarks = "UserDataStore.bookmarks"
        static let bookmarkGroups = "UserDataStore.bookmarkGroups"
        static let debugMode = "UserDataStore.debugMode"
        static let lastSelectedView = "UserDataStore.lastSelectedView"
        static let readServiceAlerts = "UserDataStore.readServiceAlerts"
        static let recentStops = "UserDataStore.recentStops"
        static let stopPreferences = "UserDataStore.stopPreferences"
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults

        self.userDefaults.register(defaults: [UserDefaultsKeys.debugMode: false])
    }

    // MARK: - Debug Mode

    public var debugMode: Bool {
        get {
            return userDefaults.bool(forKey: UserDefaultsKeys.debugMode)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.debugMode)
        }
    }

    // MARK: - Bookmark Groups

    public var bookmarkGroups: [BookmarkGroup] {
        get {
            let groups: [BookmarkGroup] = decodeUserDefaultsObjects(type: [BookmarkGroup].self, key: UserDefaultsKeys.bookmarkGroups) ?? []
            return groups.sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: UserDefaultsKeys.bookmarkGroups) // swiftlint:disable:this force_try
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
            add(bm, to: nil, index: .max)
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
            return decodeUserDefaultsObjects(type: [Bookmark].self, key: UserDefaultsKeys.bookmarks) ?? []
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: UserDefaultsKeys.bookmarks) // swiftlint:disable:this force_try
        }
    }

    public var favoritedBookmarks: [Bookmark] {
        bookmarks.filter { $0.isFavorite }
    }

    public func bookmarksInGroup(_ bookmarkGroup: BookmarkGroup?) -> [Bookmark] {
        let id = bookmarkGroup?.id ?? nil
        return bookmarks.filter { $0.groupID == id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    public func add(_ bookmark: Bookmark, to group: BookmarkGroup? = nil) {
        add(bookmark, to: group, index: .max)
    }

    // swiftlint:disable for_where

    public func checkForDuplicates(bookmark: Bookmark) -> Bool {
        for candidate in bookmarks {
            if bookmark.isEqualish(candidate) {
                return true
            }
        }
        return false
    }

    // swiftlint:enable for_where

    public func add(_ bookmark: Bookmark, to group: BookmarkGroup?, index: Int) {
        let oldGroupID = bookmark.groupID

        if let group = group {
            upsert(bookmarkGroup: group)
        }

        bookmark.groupID = group?.id ?? nil

        if let existing = findBookmark(id: bookmark.id) {
            delete(bookmark: existing)
        }

        var newGroupBookmarks = bookmarksInGroup(group)
        newGroupBookmarks.insert(bookmark, at: min(index, newGroupBookmarks.count))

        for (idx, elt) in newGroupBookmarks.enumerated() {
            if let existing = findBookmark(id: elt.id) {
                delete(bookmark: existing, reorderGroup: false)
            }

            elt.sortOrder = idx

            bookmarks.append(elt)
        }

        if oldGroupID != bookmark.groupID {
            let oldGroupBookmarks = bookmarksInGroup(findGroup(id: oldGroupID))
            for (idx, elt) in oldGroupBookmarks.enumerated() {
                if let existing = findBookmark(id: elt.id) {
                    delete(bookmark: existing, reorderGroup: false)
                }

                elt.sortOrder = idx
                bookmarks.append(elt)
            }
        }
    }

    public func delete(bookmark: Bookmark) {
        delete(bookmark: bookmark, reorderGroup: true)
    }

    private func delete(bookmark: Bookmark, reorderGroup: Bool) {
        let bookmark = findBookmark(id: bookmark.id, defaultValue: bookmark)
        guard let index = bookmarks.firstIndex(of: bookmark) else { return }

        let groupID = bookmark.groupID

        bookmarks.remove(at: index)

        if reorderGroup {
            for (idx, elt) in bookmarksInGroup(findGroup(id: groupID)).enumerated() {
                if let existing = findBookmark(id: elt.id) {
                    delete(bookmark: existing, reorderGroup: false)
                }
                elt.sortOrder = idx
                bookmarks.append(elt)
            }
        }
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

    public func findBookmark(stopID: StopID) -> Bookmark? {
        bookmarks.first { $0.stopID == stopID }
    }

    public func findBookmarks(matching searchText: String) -> [Bookmark] {
        let cleanedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return bookmarks.filter { $0.matchesQuery(cleanedText) }
    }

    public func findBookmarks(in region: Region?) -> [Bookmark] {
        guard let region = region else { return [] }
        return bookmarks.filter { $0.regionIdentifier == region.regionIdentifier }
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
            return decodeUserDefaultsObjects(type: [Stop].self, key: UserDefaultsKeys.recentStops) ?? []
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: UserDefaultsKeys.recentStops) // swiftlint:disable:this force_try
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

    // MARK: - Alarms

    public func deleteExpiredAlarms() {
        let now = Date()

        for a in alarms {
            if a.tripDate == nil {
                delete(alarm: a)
            }
            else if let tripDate = a.tripDate, tripDate < now {
                delete(alarm: a)
            }
        }
    }

    public var alarms: [Alarm] {
        get {
            return decodeUserDefaultsObjects(type: [Alarm].self, key: UserDefaultsKeys.alarms) ?? []
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: UserDefaultsKeys.alarms) // swiftlint:disable:this force_try
        }
    }

    public func add(alarm: Alarm) {
        alarms.append(alarm)
    }

    public func delete(alarm: Alarm) {
        alarms.removeAll { $0 == alarm }
    }

    // MARK: - Stop Preferences

    public func set(stopPreferences: StopPreferences, stop: Stop, region: Region) {
        let key = stopPreferencesKey(id: stop.id, region: region)
        self.stopPreferences[key] = stopPreferences
    }

    public func preferences(stopID: StopID, region: Region) -> StopPreferences {
        let prefs = stopPreferences
        let key = stopPreferencesKey(id: stopID, region: region)
        return prefs[key] ?? StopPreferences()
    }

    private func stopPreferencesKey(id: String, region: Region) -> String {
        "\(region.regionIdentifier)_\(id)"
    }

    private var stopPreferences: [String: StopPreferences] {
        get {
            return decodeUserDefaultsObjects(type: [String: StopPreferences].self, key: UserDefaultsKeys.stopPreferences) ?? [:]
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: UserDefaultsKeys.stopPreferences) // swiftlint:disable:this force_try
        }
    }

    // MARK: - View State/Last Selected Tab

    public var lastSelectedView: SelectedTab {
        get {
            guard userDefaults.contains(key: UserDefaultsKeys.lastSelectedView) else {
                return .map
            }
            let raw = userDefaults.integer(forKey: UserDefaultsKeys.lastSelectedView)
            return SelectedTab(rawValue: raw)!
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: UserDefaultsKeys.lastSelectedView)
        }
    }

    // MARK: - Service Alerts

    public func isUnread(serviceAlert: ServiceAlert) -> Bool {
        readAlerts[serviceAlert.id] ?? true
    }

    public func markRead(serviceAlert: ServiceAlert) {
        readAlerts[serviceAlert.id] = false
    }

    private var readAlerts: [String: Bool] {
        get {
            return decodeUserDefaultsObjects(type: [String: Bool].self, key: UserDefaultsKeys.readServiceAlerts) ?? [:]
        }
        set {
            try! encodeUserDefaultsObjects(newValue, key: UserDefaultsKeys.readServiceAlerts) // swiftlint:disable:this force_try
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
    private func decodeUserDefaultsObjects<T>(type: T.Type, key: String) -> T? where T: Decodable {
        do {
            let obj = try userDefaults.decodeUserDefaultsObjects(type: T.self, key: key)
            return obj
        }
        catch let error {
            Logger.error("Unable to decode \(key): \(error)")
            return nil
        }
    }

    /// Encodes an array of `Encodable` objects and stores them in user defaults.
    /// - Parameter objects: An `Encodable` object (or an array of them). For example, bookmarks.
    /// - Parameter key: The user defaults key that corresponds to the data being saved.
    private func encodeUserDefaultsObjects<T>(_ object: T, key: String) throws where T: Encodable {
        try userDefaults.encodeUserDefaultsObjects(object, key: key)
    }
}
