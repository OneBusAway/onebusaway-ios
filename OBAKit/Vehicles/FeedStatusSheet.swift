//
//  FeedStatusSheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// A sheet that displays the status of each agency's vehicle feed with filter toggles
struct FeedStatusSheet: View {
    @ObservedObject var viewModel: VehiclesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.feedStatuses) { status in
                FeedStatusRow(
                    status: status,
                    isEnabled: viewModel.isAgencyEnabled(status.id),
                    onToggle: { enabled in
                        viewModel.setAgencyEnabled(enabled, agencyID: status.id)
                    }
                )
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .navigationTitle("Feed Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.allAgenciesEnabled ? "Disable All" : "Enable All") {
                        viewModel.toggleAllAgencies()
                    }
                    .font(.subheadline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A compact row displaying the status of a single agency's feed with a toggle
struct FeedStatusRow: View {
    let status: AgencyFeedStatus
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.agencyName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if status.isSkipped {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let lastFetched = status.lastFetchedAt {
                    Text("Updated \(lastFetched, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = status.error {
                    Text(error.userFriendlyDescription)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if !status.isSkipped {
                    Text("\(status.vehicleCount) vehicles")
                        .font(.caption)
                        .foregroundStyle(status.vehicleCount > 0 ? .green : .secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
    }
}
