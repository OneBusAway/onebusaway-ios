//
//  ManageGroupsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Rename, add, delete, and rearrange bookmark groups. Always in edit mode.
/// Edits are held in the view model until `ManageGroupsViewModel.commit()`.
struct ManageGroupsView: View {
    @Bindable var viewModel: ManageGroupsViewModel

    var body: some View {
        List {
            Section {
                ForEach($viewModel.drafts) { $draft in
                    TextField(
                        OBALoc("manage_groups_controller.text_field_placeholder", value: "Group name", comment: "Placeholder text for Bookmark Group."),
                        text: $draft.name
                    )
                }
                .onMove(perform: viewModel.moveDrafts)
                .onDelete(perform: viewModel.deleteDrafts)

                Button(OBALoc("manage_groups_controller.add_group_button", value: "Add Bookmark Group", comment: "'Add Bookmark Group' button text")) {
                    viewModel.addDraft()
                }
            } footer: {
                Text(OBALoc("manage_groups_controller.groups.footer_text", value: "You can rename, add, delete, and rearrange bookmark groups. Bookmarks in deleted groups are not deleted.", comment: "Footer explanation on the Groups section of the Manage Groups controller."))
            }
        }
        .environment(\.editMode, .constant(.active))
    }
}
