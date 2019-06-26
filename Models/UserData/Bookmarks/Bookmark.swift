//
//  Bookmark.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/20/19.
//

import Foundation

/// This is a bookmark for a `Stop`.
@objc(OBABookmark) public class Bookmark: NSObject, Codable {

    /// Optional. The unique identifier for the `BookmarkGroup` to which this object belongs.
    public var groupUUID: UUID?

    /// The unique identifier for this object.
    public let uuid: UUID

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
    public let stopID: String

    /// Whether or not this `Bookmark` should be displayed in the Today widget, for example. `false` by default.
    public var isFavorite: Bool

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

    public init(name: String, regionIdentifier: Int, stop: Stop) {
        self.uuid = UUID()
        self.name = name
        self.regionIdentifier = regionIdentifier
        self.stopID = stop.id
        self.stop = stop
        self.isFavorite = false
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Bookmark else { return false }

        return
            uuid == rhs.uuid &&
            groupUUID == rhs.groupUUID &&
            name == rhs.name &&
            regionIdentifier == rhs.regionIdentifier &&
            stopID == rhs.stopID &&
            stop == rhs.stop &&
            isFavorite == rhs.isFavorite
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(uuid)
        hasher.combine(groupUUID)
        hasher.combine(name)
        hasher.combine(regionIdentifier)
        hasher.combine(stopID)
        hasher.combine(stop)
        hasher.combine(isFavorite)
        return hasher.finalize()
    }

    override public var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = ["uuid": uuid as Any, "groupUUID": groupUUID as Any, "name": name as Any, "regionIdentifier": regionIdentifier as Any, "stopID": stopID as Any, "isFavorite": isFavorite as Any]
        return "\(desc) \(props)"
    }
}
