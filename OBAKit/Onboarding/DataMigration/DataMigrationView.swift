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
    @Environment(\.coreApplication) var application
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.dismiss) var dismiss

    @State var isMigrating = false
    @State var isShowingErrorDetails = false
    @State var migrationError: Error?

    @State var isShowingReport = false
    @State var report: DataMigrator_.MigrationReport?

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
        .alert("migration error", isPresented: $isShowingErrorDetails) {
            Text(migrationError?.localizedDescription ?? "<no error>")
        }
        .sheet(item: $report) { report in
            DataMigrationResultView(results: report.viewModel())
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
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                Button {
                    Task {
                        isMigrating = true
                        await doMigration()
                        isMigrating = false
                    }
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
            .onDrop(of: [.propertyList, .xml, .xmlPropertyList], isTargeted: nil, perform: dryRunMigrationFromUserProvidedItem)
            .disabled(isMigrating)
            .background(.background)
        }
        .padding()
    }

    private func dryRunMigrationFromUserProvidedItem(_ itemProviders: [NSItemProvider]) -> Bool {
        // Only the first item will be used.
        guard let itemProvider = itemProviders.first else {
            return false
        }

        _ = itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.propertyList.identifier) { url, error in
            if let error {
                self.migrationError = error
                self.isShowingErrorDetails = true
            }

            // The data must be loaded from the URL in this closure block, per OS requirements.
            guard let url else { return }

            // swiftlint:disable force_try
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                self.migrationError = error
                self.isShowingErrorDetails = true
                return
            }

            Task(priority: .userInitiated) {
                await dryRunMigration(plistData: data)
            }
        }

        return true
    }

    /// Do a "dry run" migration with the user-provided `plist` file. The dry run report is shown afterwards.
    private func dryRunMigration(plistData data: Data) async {
        guard let region = application.currentRegion, let apiService = application.betterAPIService else {
            return
        }

        // swiftlint:disable force_try
        guard let migrator = try! DataMigrator_.asdf(data: data) else {
            return
        }

        do {
            let _report = try await migrator.performMigration(.init(forceMigration: true, regionIdentifier: region.regionIdentifier), apiService: apiService, dataStorer: nil)
            await MainActor.run {
                self.report = _report
            }
        } catch {
            await MainActor.run {
                self.migrationError = error
                self.isShowingErrorDetails = true
            }
        }
    }

    func doMigration() async {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return

        guard let region = application.currentRegion else {
            return
        }

        guard let apiService = application.betterAPIService else {
             return
        }

        let migrator = DataMigrator_(userDefaults: .standard)

        let parameters = DataMigrator_.MigrationParameters(forceMigration: false, regionIdentifier: region.regionIdentifier)

        let report: DataMigrator_.MigrationReport
        do {
            report = try await migrator.performMigration(parameters, apiService: apiService, dataStorer: application)
        } catch {
            migrationError = error
            return
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
