//
//  DataMigrationView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/2/23.
//

import SwiftUI
import OBAKitCore
import UniformTypeIdentifiers

struct DataMigrationView: View {
    // TODO: Instead of a catch-all "application" dependency, each individual dependency should be listed.
    //       In this specific view, we need `currentRegion` and `apiService` dependencies.
    @Environment(\.coreApplication) var application
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.dismiss) var dismiss

    @State var isMigrating = false

    /// Migration results are displayed in a sheet.
    @State var migrationReport: DataMigrator_.MigrationReport?

    /// Migrator errors are displayed above the [Continue] button.
    @State var migratorError: Error?

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
                label(title: "Upgrade your Recent Stops and Bookmarks to work with the latest version of the app, you only need to do this once.", systemImage: "star.square.on.square")
                label(title: "You will not be able to see your Recent Stops or Bookmarks until you upgrade.", systemImage: "bookmark.slash")
                label(title: "Upgrading may take a bit of time, and a Wi-Fi or mobile connection is required during the upgrade.", systemImage: "wifi")
            }
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
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
            .background(.background)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                if let migratorError {
                    Text(migratorError.localizedDescription)
                }

                Button {
                    doRealMigration()
                } label: {
                    if isMigrating {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 32)
                    } else {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dismiss()
                } label: {
                    Text("Not Now")
                }
            }
            .onDrop(of: [.propertyList, .xml, .xmlPropertyList], isTargeted: nil, perform: handleUserProvidedItem)
            .disabled(isMigrating)
            .background(.background)
        }
        .sheet(item: $migrationReport, onDismiss: handleReportDismiss) { report in
            DataMigrationReportView(report: report)
        }
        .padding()
    }

    private func handleReportDismiss() {
        self.dismiss()
    }

    private func handleUserProvidedItem(_ itemProviders: [NSItemProvider]) -> Bool {
        // Only the first item will be used.
        guard let itemProvider = itemProviders.first else {
            return false
        }

        _ = itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.propertyList.identifier) { url, error in
            if let error {
                self.migratorError = error
                return
            }

            // The data must be loaded from the URL in this closure block, per OS requirements.
            guard let url else { return }

            do {
                let data = try Data(contentsOf: url)
                try doDryRunMigration(plistData: data)
            } catch {
                self.migratorError = error
                return
            }
        }

        return true
    }

    /// Do a "dry run" migration with the user-provided `plist` file. The dry run report is shown afterwards, but none of the migration data will actually persist.
    private func doDryRunMigration(plistData data: Data) throws {
        let migrator = try DataMigrator_.createMigrator(fromUserDefaultsData: data)

        Task(priority: .userInitiated) {
            self.isMigrating = true
            await self.doMigration(withMigrator: migrator, isDryRun: true)
            self.isMigrating = false
        }
    }

    /// Do migration with `UserDefaults.standard`. The dry run report is shown afterwards, and the migration data is persisted.
    private func doRealMigration() {
        let migrator = DataMigrator_(userDefaults: .standard)
        Task(priority: .userInitiated) {
            self.isMigrating = true
            await self.doMigration(withMigrator: migrator, isDryRun: false)
            self.isMigrating = false
        }
    }

    private func doMigration(withMigrator migrator: DataMigrator_, isDryRun: Bool) async {
        // Dependency check
        guard let region = application.currentRegion else {
            return await MainActor.run {
                self.migratorError = UnstructuredError("No current region is set.")
            }
        }

        guard let apiService = application.betterAPIService else {
            return await MainActor.run {
                self.migratorError = UnstructuredError("No API service is set.")
            }
        }

        // Do the actual work
        let dataStorer: DataMigratorDataStorer? = isDryRun ? nil : self.application
        let forceMigration = isDryRun

        let parameters = DataMigrator_.MigrationParameters(forceMigration: forceMigration, regionIdentifier: region.regionIdentifier)

        do {
            let report = try await migrator.performMigration(parameters, apiService: apiService, dataStorer: dataStorer)
            await MainActor.run {
                self.migrationReport = report
            }
        } catch {
            await MainActor.run {
                self.migratorError = error
            }
        }
    }
}

struct DataMigrationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Text("Hello, World!")
                .sheet(isPresented: .constant(true)) {
                    DataMigrationView()
                }
        }
    }
}
