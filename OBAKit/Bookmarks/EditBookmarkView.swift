//
//  EditBookmarkView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The bookmark editor's form: name, stop ID, Today View switch, and group.
/// Saving and cancelling belong to `EditBookmarkViewController`.
struct EditBookmarkView: View {
    @Bindable var viewModel: EditBookmarkViewModel

    @State private var isAddingGroup = false
    @State private var newGroupName = ""

    private var nameTitle: String {
        OBALoc("edit_bookmark_controller.name_section.header_title", value: "Bookmark Name", comment: "Title of the Bookmark Name header.")
    }

    var body: some View {
        Form {
            Section {
                TextField("", text: $viewModel.name)
                    .accessibilityLabel(nameTitle)
            } header: {
                Text(nameTitle)
            }

            // Read-only stop ID so a failing bookmark can be matched to the API path (#1421).
            Section {
                CopyableValueRow(
                    title: OBALoc("edit_bookmark_controller.stop_id_row.title", value: "Stop ID", comment: "Title of the read-only Stop ID row on the Edit Bookmark screen."),
                    value: viewModel.stopID,
                    accessibilityHint: OBALoc("edit_bookmark_controller.stop_id_row.accessibility_hint", value: "Copies the stop ID.", comment: "VoiceOver hint for the read-only Stop ID row on the Edit Bookmark screen. Activating the row copies the stop ID.")
                )
            } header: {
                Text(OBALoc("edit_bookmark_controller.stop_id_section.header_title", value: "Stop ID", comment: "Header above the read-only Stop ID on the Edit Bookmark screen."))
            } footer: {
                Text(OBALoc("edit_bookmark_controller.stop_id_section.footer", value: "Used when loading arrivals for this bookmark. Tap to copy.", comment: "Footer under the Stop ID row on the Edit Bookmark screen."))
            }

            Section {
                Toggle(
                    OBALoc("edit_bookmark_controller.show_in_today_view_switch_title", value: "Show in Today View widget", comment: "Title next to the switch that toggles whether a bookmark will appear in the today view."),
                    isOn: $viewModel.isFavorite
                )
            }

            Section {
                Picker(selection: $viewModel.selectedGroupID) {
                    ForEach(viewModel.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                    Text(OBALoc("edit_bookmark_controller.no_group_row", value: "(No Group)", comment: "Don't add this bookmark to a group."))
                        .tag(UUID?.none)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(OBALoc("edit_bookmark_controller.group_section.header_title", value: "Bookmark Group", comment: "Title of the Bookmark Group header."))
            }

            Section {
                Button(OBALoc("edit_bookmark_controller.add_group_button_title", value: "Add Bookmark Group", comment: "Title of the button that lets the user add a new Bookmark Group.")) {
                    newGroupName = ""
                    isAddingGroup = true
                }
            }
        }
        .alert(OBALoc("add_group_alert.title", value: "Add Group", comment: "Title of the Add Bookmark Group controller"), isPresented: $isAddingGroup) {
            TextField(OBALoc("add_group_alert.placeholder", value: "Bookmark Group Title", comment: "Text field placeholder on the Add Group Alert."), text: $newGroupName)
            Button(Strings.cancel, role: .cancel) {}
            Button(Strings.save) {
                viewModel.addGroup(named: newGroupName)
            }
        }
    }
}
