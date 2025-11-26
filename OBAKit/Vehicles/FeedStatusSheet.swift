//
//  FeedStatusSheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// A sheet that displays the status of each agency's vehicle feed
struct FeedStatusSheet: View {
    let feedStatuses: [AgencyFeedStatus]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(feedStatuses) { status in
                FeedStatusRow(status: status)
            }
            .navigationTitle("Feed Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A row displaying the status of a single agency's feed
struct FeedStatusRow: View {
    let status: AgencyFeedStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.agencyName)
                    .font(.headline)
                Spacer()
                statusIcon
            }

            Text("ID: \(status.id)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastFetched = status.lastFetchedAt {
                Text("Updated \(lastFetched, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = status.error {
                Label(error.userFriendlyDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("\(status.vehicleCount) vehicles")
                    .font(.caption)
                    .foregroundStyle(status.vehicleCount > 0 ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if status.error != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        } else if status.vehicleCount > 0 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
