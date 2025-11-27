//
//  MapStatusView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/26/25.
//

import SwiftUI

extension VehiclesMapView {
    struct StatusView: View {
        @EnvironmentObject var viewModel: VehiclesViewModel

        var body: some View {
            MapContainerView {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                            Text("Loading...")
                                .font(.caption)
                        }
                    } else if let error = viewModel.error {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    } else {
                        Text("\(viewModel.vehicles.count) vehicles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let lastUpdated = viewModel.lastUpdated {
                            Text("Updated \(lastUpdated, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if viewModel.totalAgencyCount > 0 {
                            Text("Agencies: \(viewModel.enabledAgencyCount) of \(viewModel.totalAgencyCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}
