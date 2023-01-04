//
//  DataMigrationResultView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/4/23.
//

import SwiftUI
import OBAKitCore

struct DataMigrationResultView: View {

    var results: [DataMigrationResultGroupViewModel]

    var body: some View {
        List {
            ForEach(results) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        listView(item)
                    }
                }
            }
        }
    }

    @ViewBuilder func listView(_ item: DataMigrationResultItem) -> some View {
        DisclosureGroup {
            if let error = item.error {
                Text(error.localizedDescription)
            } else {
                Text("No problems.")
            }
        } label: {
            Label(item.title, systemImage: item.systemImageName)
        }
    }
}

struct DataMigrationResultView_Previews: PreviewProvider {
    static var previews: some View {
        DataMigrationResultView(results: Self.sampleData)
    }

    static var sampleData: [DataMigrationResultGroupViewModel] {
        return [
            .init(title: "Metadata", items: [
                .init(systemImageName: "checkmark.diamond", title: "User ID", subtitle: nil),
                .init(systemImageName: "checkmark.diamond", title: "Region", subtitle: nil)
            ])
        ]
    }
}
