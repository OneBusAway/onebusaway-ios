//
//  BookmarksView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBASharedCore

struct BookmarksView: View {
    @StateObject private var viewModel: BookmarksViewModel
    
    init() {
        _viewModel = StateObject(wrappedValue: BookmarksViewModel())
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.bookmarks.isEmpty {
                    emptyStateView
                } else {
                    bookmarksList
                }
            }
            .navigationTitle("Bookmarks")
            .task {
                await viewModel.refreshData()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Bookmarks")
                .font(.headline)
            Text("Add bookmarks in the iOS app")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var bookmarksList: some View {
        List {
            ForEach(viewModel.bookmarks) { bookmark in
                NavigationLink {
                    StopArrivalsView(stopID: bookmark.stopID, stopName: bookmark.name)
                } label: {
                    BookmarkRow(bookmark: bookmark)
                }
            }
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue.gradient)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if let routeName = bookmark.routeShortName {
                    HStack(spacing: 4) {
                        Text("Route \(routeName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let headsign = bookmark.tripHeadsign {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(headsign)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else if let stop = bookmark.stop {
                    Text(stop.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    BookmarksView()
}
