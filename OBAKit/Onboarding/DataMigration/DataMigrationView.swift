//
//  DataMigrationView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/2/23.
//

import SwiftUI
import OBAKitCore

struct DataMigrationView: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @ViewBuilder
    private func label(title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(Image(systemName: systemImage)) + Text(" ") + Text(title)
        } else {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 30))
                    .frame(width: 50, height: 50, alignment: .center)
                Text(title)
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "arrow.up.doc.on.clipboard")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                        .padding(16)
                        .background(Color(uiColor: ThemeColors.shared.brand))
                        .clipShape(Circle())

                    Text("Data Upgrade")
                        .font(.largeTitle)
                        .bold()
                }
                .frame(maxWidth: .infinity)     // center the view
                .multilineTextAlignment(.center)
            }
            .listRowSeparator(.hidden)

            Section {
                label(title: "Upgrade your Recent Stops and Bookmarks to work with the latest version of the app.", systemImage: "star.square.on.square")
                label(title: "You will not be able to see your Recent Stops or Bookmarks until you upgrade.", systemImage: "bookmark.slash")
                label(title: "Upgrading may take a bit of time, and a Wi-Fi or mobile connection is required while upgrading.", systemImage: "wifi")
            }
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                Button {
                    print("migrating")
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    print("ok :(")
                } label: {
                    Text("Not Now")
                }
            }
            .background(.background)
        }
        .padding()
    }
}

struct DataMigrationView_Previews: PreviewProvider {
    static var previews: some View {
        DataMigrationView()
    }
}
