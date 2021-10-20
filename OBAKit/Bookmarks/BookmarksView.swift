//
//  BookmarksView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/6/21.
//

import SwiftUI
import OBAKitCore

struct BookmarksView: View {
    @Environment(\.coreApplication) var application
    @ObservedObject var bookmarksDAO = BookmarksDataModel()
    @State var isEditingSections: Bool = false

    var body: some View {
        List(bookmarksDAO.groups) { group in
            if isEditingSections {
                editingBookmarks(for: group)
            } else {
                bookmarkSection(for: group)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Bookmarks")
        .listStyle(.plain)
        .toolbar {
            Button("Toggle edit") {
                isEditingSections.toggle()
            }
        }
        .onAppear {
            bookmarksDAO.reloadData()
        }
    }

    func bookmarkSection(for group: BookmarkGroupViewModel) -> some View {
        Section {
            ForEach(group.bookmarks) { bookmark in
                if case let BookmarkViewModel.stop(stop) = bookmark {
                    StopBookmarkView(viewModel: stop)
                } else if case let BookmarkViewModel.trip(trip) = bookmark {
                    TripBookmarkView(viewModel: trip)
                }
            }
        } header: {
            Text(group.name)
                .textCase(.uppercase)
                .font(.headline)
                .padding([.top, .bottom], 4)
        }
    }

    func editingBookmarks(for group: BookmarkGroupViewModel) -> some View {
        Text(group.name)
            + Text(" (")
            + Text("\(group.bookmarks.count)")
            + Text(")")
    }

}

//struct BookmarksView_Previews: PreviewProvider {
//    static var previews: some View {
//        NavigationView {
//            BookmarksView(viewModel: BookmarkGroupViewModel.previewGroup)
//        }
//    }
//}
