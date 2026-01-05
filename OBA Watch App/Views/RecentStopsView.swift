//
//  RecentStopsView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBASharedCore
struct RecentStopsView: View {
    @StateObject private var viewModel: RecentStopsViewModel
    
    init() {
        _viewModel = StateObject(wrappedValue: RecentStopsViewModel())
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.recentStops.isEmpty {
                    emptyStateView
                } else {
                    recentStopsList
                }
            }
            .navigationTitle("Recent Stops")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Recent Stops")
                .font(.headline)
            Text("View stops to see them here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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
        }
    }
}

struct RecentStopRow: View {
    let stop: OBAStop
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stop.name)
                .font(.headline)
                .lineLimit(2)
            
            if let code = stop.code {
                Text("Stop \(code)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    RecentStopsView()
}

