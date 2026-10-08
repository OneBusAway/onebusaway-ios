//
//  ManageBookmarksView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Rename, delete, and rearrange bookmarks, including dragging a bookmark from
/// one group into another. Always in edit mode; changes are saved as they're made.
struct ManageBookmarksView: View {
    let viewModel: ManageBookmarksViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.rows) { row in
                    switch row {
                    case .header(_, let title):
                        GroupHeaderRow(title: title)
                    case .bookmark(let bookmark):
                        BookmarkNameRow(bookmark: bookmark) { id, name in
                            viewModel.saveNameChange(bookmarkID: id, newName: name)
                        }
                    }
                }
                .onMove(perform: viewModel.moveRows)
                .onDelete(perform: viewModel.deleteRows)
            } footer: {
                Text(OBALoc("manage_bookmarks.controller_footer", value: "You can rearrange and delete Bookmarks from this screen.", comment: "Explains the purpose of the Manage Bookmarks controller"))
            }
        }
        .environment(\.editMode, .constant(.active))
    }
}

/// A group's title, styled like a section header. It's a row rather than a
/// `Section` header so bookmarks can be dragged past it into another group.
private struct GroupHeaderRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .moveDisabled(true)
            .deleteDisabled(true)
    }
}

private struct BookmarkNameRow: View {
    @Bindable var bookmark: ManageBookmarksViewModel.EditableBookmark
    let save: (_ id: UUID, _ name: String) -> Void

    var body: some View {
        TextField("", text: $bookmark.name)
            .onChange(of: bookmark.name) { _, name in
                save(bookmark.id, name)
            }
    }
}
