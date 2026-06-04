//
//  ManageGroupsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Shared ViewModel for creating, renaming, reordering, and deleting bookmark groups.
///
/// Owns: the live list of `BookmarkGroup`s and the rules for turning ordered form
/// rows back into groups (preserving identity for existing groups, minting new
/// UUIDs for new ones, and skipping blank rows).
@MainActor
final class ManageGroupsViewModel {

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    // MARK: - Data Access

    var bookmarkGroups: [BookmarkGroup] {
        application.userDataStore.bookmarkGroups
    }

    // MARK: - Group Construction

    /// Converts an ordered sequence of (tag, value) pairs — as read from the Eureka form —
    /// into `BookmarkGroup` objects. Rows with empty or whitespace-only names are skipped.
    /// Existing groups are identified by their UUID tag and a new `BookmarkGroup` is
    /// constructed reusing that UUID so identity is preserved when `replaceBookmarkGroups`
    /// later merges these into the store; rows without a valid UUID tag produce a new
    /// group with a fresh ID.
    func groups(from rows: [(tag: String?, value: String?)]) -> [BookmarkGroup] {
        var result = [BookmarkGroup]()
        var sortOrder = 0
        for row in rows {
            guard let name = row.value, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let id = UUID(optionalUUIDString: row.tag) ?? UUID()
            result.append(BookmarkGroup(name: name, id: id, sortOrder: sortOrder))
            sortOrder += 1
        }
        return result
    }

    // MARK: - Mutation

    /// Replaces the current bookmark groups with `newGroups`, preserving sort order.
    func replaceGroups(_ newGroups: [BookmarkGroup]) {
        application.userDataStore.replaceBookmarkGroups(with: newGroups)
    }
}
