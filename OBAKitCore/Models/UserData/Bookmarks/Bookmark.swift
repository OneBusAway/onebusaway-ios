//
//  Bookmark.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// @unchecked Sendable: user-data model whose mutable properties are only written on the
// main actor (user edits via UserDataStore); background consumers treat instances as
// read-only snapshots.
/// This is a bookmark for a `Stop` or a trip.
@objc(OBABookmark) public final class Bookmark: NSObject, Identifiable, Codable, @unchecked Sendable {

    /// Optional. The unique identifier for the `BookmarkGroup` to which this object belongs.
    public var groupID: UUID?

    /// The unique identifier for this object.
    public let id: UUID

    /// The user-visible name of this object.
    public var name: String

    /// The `Region` ID for this object.
    ///
    /// `Bookmark`s are scoped by `Region`, so that you won't see Puget Sound bookmarks while in San Diego.
    public let regionIdentifier: Int

    /// The `Stop` identifier.
    ///
    /// This value, in conjunction with the `regionIdentifier`, allows us to retrieve the information that is pointed
    /// to by this object.
    public let stopID: StopID

    /// Whether or not this `Bookmark` should be displayed in the Today widget, for example. `false` by default.
    ///
    /// - Note: Despite the name, this is the "Show in Today View" toggle, not a
    ///   general-purpose favourite. See `isPinned` for the home sheet's pinning.
    public var isFavorite: Bool

    /// Whether the user has pinned this `Bookmark` to the top of the home sheet's
    /// bookmarks section. `false` by default.
    ///
    /// Distinct from `isFavorite`, which drives widget visibility — pinning is
    /// purely about placement on the home sheet, and conflating the two would
    /// change what appears in the user's widget.
    public var isPinned: Bool

    /// The order in which this `Bookmark` is sorted in. By default, this value is set to be `Int.max`
    ///
    /// - Note: This is a *per-group* index — `UserDataStore.bookmarksInGroup(_:)`
    ///   renumbers each group from zero — so it is not comparable across groups.
    public var sortOrder: Int

    /// When this `Bookmark` was created.
    ///
    /// Recorded because `sortOrder` can't answer "which of these is newest":
    /// a new bookmark is appended to the end of its group, and the user can
    /// reorder the list afterwards. Surfaces that need most-recent-first — the
    /// home sheet's bookmarks preview, which shows only a handful — order by this.
    ///
    /// `Bookmark`s persisted before this property existed decode as
    /// `.distantPast`, so they sort after anything created since and keep their
    /// own relative order.
    public let dateCreated: Date

    /// This object stores a complete copy of its underlying `Stop` in order to be able to show additional information
    /// to the user.
    ///
    /// - Note: The underlying `stopID` of a `Bookmark` cannot be changed. If you try to update a `Bookmark`
    ///         with a `stop` whose `id` does not match `stopID`, the change will be rejected.
    public var stop: Stop {
        didSet {
            if stop.id != stopID {
                stop = oldValue
            }
        }
    }

    // MARK: - Trip Bookmark Properties

    public let routeShortName: String?
    public let tripHeadsign: String?
    public let routeID: RouteID?

    // MARK: - Init

    public convenience init(name: String, regionIdentifier: Int, arrivalDeparture: ArrivalDeparture, dateCreated: Date = Date()) {
        self.init(
            name: name,
            regionIdentifier: regionIdentifier,
            arrivalDeparture: arrivalDeparture,
            stop: arrivalDeparture.stop,
            dateCreated: dateCreated
        )
    }

    public convenience init(name: String, regionIdentifier: Int, stop: Stop, dateCreated: Date = Date()) {
        self.init(
            name: name,
            regionIdentifier: regionIdentifier,
            arrivalDeparture: nil,
            stop: stop,
            dateCreated: dateCreated
        )
    }

    /// `dateCreated` is injectable so tests can pin an ordering instead of
    /// racing the clock; production callers take the default.
    public init(name: String, regionIdentifier: Int, arrivalDeparture: ArrivalDeparture?, stop: Stop, dateCreated: Date = Date()) {
        if let arrivalDeparture = arrivalDeparture {
            self.routeShortName = arrivalDeparture.routeShortName
            self.routeID = arrivalDeparture.routeID
            self.tripHeadsign = arrivalDeparture.tripHeadsign
        }
        else {
            self.routeShortName = nil
            self.routeID = nil
            self.tripHeadsign = nil
        }

        self.stop = stop
        self.stopID = stop.id
        self.isFavorite = false
        self.isPinned = false
        self.name = name
        self.regionIdentifier = regionIdentifier
        self.id = UUID()
        self.sortOrder = .max
        self.dateCreated = dateCreated
    }

    private enum CodingKeys: String, CodingKey {
        case groupID, isFavorite, isPinned, name, regionIdentifier, stop, stopID, id, sortOrder, dateCreated

        // Trip bookmark keys
        case routeShortName, tripHeadsign, routeID
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        groupID = try? container.decodeIfPresent(UUID.self, forKey: .groupID)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        // Absent from bookmarks written before pinning existed; nothing was
        // pinned then, so `false` is the truthful default.
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        name = try container.decode(String.self, forKey: .name)
        regionIdentifier = try container.decode(Int.self, forKey: .regionIdentifier)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        stop = try container.decode(Stop.self, forKey: .stop)
        stopID = try container.decode(StopID.self, forKey: .stopID)
        id = try container.decode(UUID.self, forKey: .id)
        // Absent from bookmarks written before this property existed. Falling back
        // to `.distantPast` — rather than "now" — keeps a decode from making every
        // stored bookmark look freshly created, which would scramble
        // most-recent-first ordering on the first launch after upgrading.
        dateCreated = try container.decodeIfPresent(Date.self, forKey: .dateCreated) ?? .distantPast

        routeShortName = try container.decodeIfPresent(String.self, forKey: .routeShortName)
        tripHeadsign = try container.decodeIfPresent(String.self, forKey: .tripHeadsign)
        routeID = try container.decodeIfPresent(RouteID.self, forKey: .routeID)
    }

    /// Returns `true` if the receiver's contents match the contents of `bookmark`.
    ///
    /// i.e. they have identical contents, even though they may not be `==` equal.
    /// - Parameter bookmark: The bookmark to compare the receiver to.
    public func isEqualish(_ bookmark: Bookmark) -> Bool {
        return
            name == bookmark.name &&
            regionIdentifier == bookmark.regionIdentifier &&
            stopID == bookmark.stopID &&
            routeShortName == bookmark.routeShortName &&
            tripHeadsign == bookmark.tripHeadsign &&
            routeID == bookmark.routeID
    }

    /// - Note: `dateCreated` is deliberately excluded here and from `hash`. It's
    ///   provenance, not content — two bookmarks that differ only in when they
    ///   were made are the same bookmark to a user — and `Date` loses sub-second
    ///   precision through the store's encoder, so including it would make a
    ///   round-tripped bookmark unequal to the one that was written.
    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Bookmark else { return false }

        return
            id == rhs.id &&
            groupID == rhs.groupID &&
            name == rhs.name &&
            regionIdentifier == rhs.regionIdentifier &&
            sortOrder == rhs.sortOrder &&
            stopID == rhs.stopID &&
            stop == rhs.stop &&
            isFavorite == rhs.isFavorite &&
            isPinned == rhs.isPinned &&
            routeShortName == rhs.routeShortName &&
            routeID == rhs.routeID &&
            tripHeadsign == rhs.tripHeadsign
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(groupID)
        hasher.combine(name)
        hasher.combine(regionIdentifier)
        hasher.combine(stopID)
        hasher.combine(stop)
        hasher.combine(isFavorite)
        hasher.combine(isPinned)
        hasher.combine(routeShortName)
        hasher.combine(routeID)
        hasher.combine(sortOrder)
        hasher.combine(tripHeadsign)
        return hasher.finalize()
    }

    public override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "id", value: id)
        descriptionBuilder.add(key: "groupID", value: groupID)
        descriptionBuilder.add(key: "name", value: name)
        descriptionBuilder.add(key: "regionIdentifier", value: regionIdentifier)
        descriptionBuilder.add(key: "stopID", value: stopID)

        descriptionBuilder.add(key: "isFavorite", value: isFavorite)
        descriptionBuilder.add(key: "isPinned", value: isPinned)
        descriptionBuilder.add(key: "routeShortName", value: routeShortName)
        descriptionBuilder.add(key: "routeID", value: routeID)
        descriptionBuilder.add(key: "sortOrder", value: sortOrder)
        descriptionBuilder.add(key: "dateCreated", value: dateCreated)
        descriptionBuilder.add(key: "tripHeadsign", value: tripHeadsign)
        return descriptionBuilder.description
    }

    public var isTripBookmark: Bool {
        routeShortName != nil && routeID != nil && tripHeadsign != nil
    }
}
