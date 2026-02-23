//
//  BookmarksView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBAKitCore

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
            .navigationTitle(OBALoc("common.bookmarks", value: "Bookmarks", comment: "Title for the Bookmarks screen"))
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
            Text(OBALoc("bookmarks.no_bookmarks", value: "No Bookmarks", comment: "Empty state title for bookmarks"))
                .font(.headline)
            Text(OBALoc("bookmarks.add_in_ios_app", value: "Add bookmarks in the iOS app", comment: "Empty state description for bookmarks"))
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
    let bookmark: WatchBookmark
    
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
                        Text(String(format: OBALoc("common.route_fmt", value: "Route %@", comment: "Route name format"), routeName))
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
                } else if let stopObj = bookmark.stop {
                    Text(stopObj.name)
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
