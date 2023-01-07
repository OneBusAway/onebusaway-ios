//
//  DataMigrationReportView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/4/23.
//

import SwiftUI
import OBAKitCore

struct DataMigrationReportView: View {

    var reports: [DataMigrationReportGroup]

    var numberOfSuccessItems: Int
    var numberOfErrorItems: Int

    init(report: DataMigrator.MigrationReport) {
        self.init(reports: report.viewModel())
    }

    init(reports: [DataMigrationReportGroup]) {
        self.reports = reports

        var numberOfSuccessItems = 0
        var numberOfErrorItems = 0
        for report in reports {
            for item in report.items {
                if item.error == nil {
                    numberOfSuccessItems += 1
                } else {
                    numberOfErrorItems += 1
                }
            }
        }

        self.numberOfSuccessItems = numberOfSuccessItems
        self.numberOfErrorItems = numberOfErrorItems
    }

    @Environment(\.dismiss) var dismiss
    @State var isViewingReport = false

    var body: some View {
        Group {
            if isViewingReport {
                report
            } else {
                Spacer()
            }
        }
        .safeAreaInset(edge: .top) {
            OnboardingHeaderView(imageSystemName: "checkmark", headerText: OBALoc("data_migration_bulletin.finished_loading", value: "Data upgrade complete!", comment: "This comment is displayed after the user's data is upgraded in the DataMigrationBulletinPage."))
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Text(Strings.dismiss)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)

                if !isViewingReport {
                    Button(OBALoc("data_migration_bulletin.view_report_button", value: "View Report", comment: "Button title to let the user view a data migration report.")) {
                        isViewingReport = true
                    }
                }
            }
            .background(.background)
        }
        .padding()
    }

    var report: some View {
        List {
            Section("Summary") {
                if numberOfErrorItems == 0 {
                    Text("All \(numberOfSuccessItems) successful")
                } else {
                    Text("\(numberOfErrorItems) failures")
                    Text("\(numberOfSuccessItems) successes")
                }
            }

            ForEach(reports) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        listView(item)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder func listView(_ item: DataMigrationReportItem) -> some View {
        DisclosureGroup {
            if let error = item.error {
                Text(error.localizedDescription)
            }
        } label: {
            Label(item.title, systemImage: item.systemImageName)
                .symbolVariant(item.error == nil ? .none : .fill)
                .foregroundColor(item.error == nil ? Color.primary : Color.red)
        }
    }
}

struct DataMigrationReportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DataMigrationReportView(reports: Self.sampleData)
        }
    }

    static var sampleData: [DataMigrationReportGroup] {
        return [
            .init(title: "Metadata", items: [
                .init(systemImageName: "checkmark.diamond", title: "User ID", subtitle: nil),
                .init(systemImageName: "checkmark.diamond", title: "Region", subtitle: nil)
            ])
        ]
    }
}
