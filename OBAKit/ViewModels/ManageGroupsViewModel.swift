//
//  ManageGroupsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
import OBAKitCore

/// Shared ViewModel for creating, renaming, reordering, and deleting bookmark groups.
///
/// Owns: the editable `drafts` the Groups screen shows, and the rules for turning
/// them back into groups (preserving identity for existing groups, minting new
/// UUIDs for new ones, and skipping blank rows). Edits stay in `drafts` until
/// `commit()`, which the screen calls when the rider leaves it.
@MainActor
@Observable
final class ManageGroupsViewModel {

    /// One editable row on the Groups screen.
    struct GroupDraft: Identifiable, Equatable {
        let id: UUID
        var name: String
    }

    @ObservationIgnored private let application: Application

    /// The rows being edited, in display order.
    var drafts: [GroupDraft] = []

    init(application: Application) {
        self.application = application
        reloadDrafts()
    }

    // MARK: - Editing

    /// Rebuilds `drafts` from the store. With no groups yet, offers one blank row
    /// so the rider has somewhere to type.
    func reloadDrafts() {
        drafts = bookmarkGroups.map { GroupDraft(id: $0.id, name: $0.name) }
        if drafts.isEmpty {
            addDraft()
        }
    }

    func addDraft() {
        drafts.append(GroupDraft(id: UUID(), name: ""))
    }

    func moveDrafts(from source: IndexSet, to destination: Int) {
        drafts.move(fromOffsets: source, toOffset: destination)
    }

    func deleteDrafts(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
    }

    /// Writes `drafts` to the store. Bookmarks in deleted groups are kept and
    /// become ungrouped.
    func commit() {
        replaceGroups(groups(from: drafts))
    }

    // MARK: - Data Access

    var bookmarkGroups: [BookmarkGroup] {
        application.userDataStore.bookmarkGroups
    }

    // MARK: - Group Construction

    /// Converts drafts into `BookmarkGroup`s numbered in order, skipping drafts
    /// with empty or whitespace-only names. Each group keeps its draft's `id`, so
    /// `replaceBookmarkGroups` updates existing groups rather than replacing them.
    func groups(from drafts: [GroupDraft]) -> [BookmarkGroup] {
        drafts
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { BookmarkGroup(name: $1.name, id: $1.id, sortOrder: $0) }
    }

    // MARK: - Mutation

    /// Replaces the current bookmark groups with `newGroups`, preserving sort order.
    func replaceGroups(_ newGroups: [BookmarkGroup]) {
        application.userDataStore.replaceBookmarkGroups(with: newGroups)
    }
}
