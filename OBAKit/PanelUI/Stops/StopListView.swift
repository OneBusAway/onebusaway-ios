//
//  StopListView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/28/25.
//

import SwiftUI
import OBAKitCore

struct StopListView: View {
    let title: String
    let stops: [Stop]
    let onStopSelected: (Stop) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if !stops.isEmpty {
                    Text("\(stops.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if stops.isEmpty {
                EmptyStateView(iconName: "mappin.slash", title: "No Stops in This Area", text: "Zoom out or pan around to see nearby stops.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(stops.prefix(5)) { stop in
                        StopRowView(stop: stop) {
                            onStopSelected(stop)
                        }
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}
