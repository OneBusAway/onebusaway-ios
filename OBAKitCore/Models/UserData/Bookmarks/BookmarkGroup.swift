//
//  BookmarkGroup.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/20/19.
//

import Foundation

/// Represents a collection of `Bookmark`s. For instance, the user might have groups named "To Work" and "To Home".
@objc(OBABookmarkGroup)
public class BookmarkGroup: NSObject, Codable, Identifiable {

    /// The user-facing name of the group.
    public var name: String

    /// A unique identifier for this group.
    public let id: UUID

    /// The sort order of this object.
    public let sortOrder: Int

    /// Creates a new `BookmarkGroup`
    ///
    /// - Parameter name: The user-facing name of the `BookmarkGroup`.
    /// - Parameter sortOrder: The ordering of this object.
    public convenience init(name: String, sortOrder: Int) {
        self.init(name: name, id: UUID(), sortOrder: sortOrder)
    }

    /// Creates a new `BookmarkGroup`.
    /// - Parameter name: The user-facing name of the `BookmarkGroup`.
    /// - Parameter id: A unique identifier that represents this object.
    /// - Parameter sortOrder: The ordering of this object.
    public init(name: String, id: UUID, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    // MARK: - Equatable and Hashable

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? BookmarkGroup else {
            return false
        }

        return name == rhs.name && id == rhs.id && sortOrder == rhs.sortOrder
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(id)
        hasher.combine(sortOrder)
        return hasher.finalize()
    }

    // MARK: - Debug

    override public var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = ["name": name as Any, "sortOrder": sortOrder as Any, "id": id as Any]
        return "\(desc) \(props)"
    }
}
