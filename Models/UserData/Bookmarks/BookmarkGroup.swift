//
//  BookmarkGroup.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/20/19.
//

import Foundation

/// Represents a collection of `Bookmark`s. For instance, the user might have groups named "To Work" and "To Home".
@objc(OBABookmarkGroup)
public class BookmarkGroup: NSObject, Codable {

    /// The user-facing name of the group.
    public var name: String

    /// A unique identifier for this group.
    public let uuid: UUID

    /// Creates a new `BookmarkGroup`
    ///
    /// - Parameter name: The user-facing name of the `BookmarkGroup`.
    public init(name: String) {
        self.uuid = UUID()
        self.name = name
    }

    // MARK: - Equatable and Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? BookmarkGroup else {
            return false
        }

        return
            name == rhs.name &&
            uuid == rhs.uuid
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(uuid)
        return hasher.finalize()
    }
}
