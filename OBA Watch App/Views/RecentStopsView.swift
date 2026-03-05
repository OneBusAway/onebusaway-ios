//
//  RecentStopsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBAKitCore
struct RecentStopsView: View {
    @ObservedObject private var viewModel = RecentStopsViewModel.shared
    
    var body: some View {
        Group {
            if viewModel.recentStops.isEmpty {
                emptyStateView
            } else {
                recentStopsList
            }
        }
        .navigationTitle(OBALoc("recent_stops.title", value: "Recent Stops", comment: "Title for recent stops screen"))
    }
    
    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: "clock",
            title: OBALoc("recent_stops.no_recent_stops", value: "No Recent Stops", comment: "Empty state title for recent stops"),
            message: OBALoc("recent_stops.view_stops_instruction", value: "View stops to see them here", comment: "Instruction for recent stops")
        )
    }
    
    private var recentStopsList: some View {
        List {
            ForEach(viewModel.recentStops) { stop in
                NavigationLink {
                    StopArrivalsView(stopID: stop.id, stopName: stop.name)
                } label: {
                    RecentStopRow(stop: stop)
                }
            }
            .onDelete { indexSet in
                viewModel.removeRecentStop(at: indexSet)
            }
        }
        .listStyle(.carousel)
    }
}

struct RecentStopRow: View {
    let stop: OBAStop
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "bus.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                
                if let routes = stop.routeNames {
                    Text(routes)
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                } else if let code = stop.code {
                    Text(String(format: OBALoc("recent_stops.stop_code_fmt", value: "Stop %@", comment: "Stop code format"), code))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecentStopsView()
}
