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
    enum MigrationTask: Equatable {
        /// Creates a fake `UserDefaults` based on the plist at the path and performs a migration dry-run.
        case userDefaultsPlistFromData(Data)

        /// Performs a real migration, using `UserDefaults.standard`.
        case userDefaultsStandard
    }

    // TODO: Instead of a catch-all "application" dependency, each individual dependency should be listed.
    //       In this specific view, we need `currentRegion` and `apiService` dependencies.
    @Environment(\.coreApplication) var application
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.dismiss) var dismiss

    /// Migration results are displayed in a sheet.
    @State var migrationReport: DataMigrator.MigrationReport?

    /// Migrator errors are displayed above the [Continue] button.
    @State var migratorError: Error?

    /// The Migration task to perform. Setting this will trigger the view's `.task` modifier.
    @State var activeMigrationTask: MigrationTask?

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
                    self.activeMigrationTask = .userDefaultsStandard
                } label: {
                    if activeMigrationTask != nil {
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
            .disabled(activeMigrationTask != nil)
            .background(.background)
        }
        .sheet(item: $migrationReport, onDismiss: handleReportDismiss) { report in
            DataMigrationReportView(report: report)
        }
        .padding()
        .task(id: activeMigrationTask, priority: .userInitiated, doMigrationTask)
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

            guard let url else { return }

            // The data must be loaded in this closure block, per OS requirements.
            do {
                let data = try Data(contentsOf: url)
                self.activeMigrationTask = .userDefaultsPlistFromData(data)
            } catch {
                self.migratorError = error
            }
        }

        return true
    }

    @Sendable
    private func doMigrationTask() async {
        guard let activeMigrationTask else {
            return
        }

        do {
            let report: DataMigrator.MigrationReport
            switch activeMigrationTask {
            case .userDefaultsPlistFromData(let data):
                let migrator = try DataMigrator.createMigrator(fromUserDefaultsData: data)
                report = try await self.doMigration(withMigrator: migrator, isDryRun: true)
            case .userDefaultsStandard:
                report = try await self.doMigration(withMigrator: .standard, isDryRun: false)
            }

            await MainActor.run {
                self.migrationReport = report
            }
        } catch {
            await MainActor.run {
                self.migratorError = error
            }
        }

        // When finished, set this back to nil.
        self.activeMigrationTask = nil
    }

    private func doMigration(withMigrator migrator: DataMigrator, isDryRun: Bool) async throws -> DataMigrator.MigrationReport {
        // Dependency check
        guard let region = application.currentRegion else {
            throw UnstructuredError("No current region is set.")
        }

        guard let apiService = application.betterAPIService else {
            throw UnstructuredError("No API service is set.")
        }

        // Do the actual work
        let delegate: DataMigrationDelegate? = isDryRun ? nil : self.application
        let forceMigration = isDryRun

        let parameters = DataMigrator.MigrationParameters(forceMigration: forceMigration, regionIdentifier: region.regionIdentifier, delegate: delegate)
        return try await  migrator.performMigration(parameters, apiService: apiService)
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
