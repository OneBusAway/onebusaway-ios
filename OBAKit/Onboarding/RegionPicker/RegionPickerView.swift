//
//  RegionPickerView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/2/23.
//

import MapKit
import SwiftUI
import OBAKitCore

struct RegionPickerView<Provider: RegionProvider>: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var regionProvider: Provider

    // MARK: - Constants
    // These icons must match, for continuity. The user gets the meaning of these
    // icons from the More Options menu, and there is no explanation text when
    // displayed on the list.
    private let inactiveRegionSystemImageName = "slash.circle.fill"
    private let experimentalRegionSystemImageName = "testtube.2"

    // MARK: - Filters
    @State private var showInactiveRegions = false
    @State private var showExperimentalRegions = false

    var filteredRegions: [Region] {
        var regions = regionProvider.allRegions

        if !showInactiveRegions {
            regions.removeAll(where: { $0.isActive == false })
        }

        if !showExperimentalRegions {
            regions.removeAll(where: \.isExperimental)
        }

        return regions
    }

    /// The currently selected region.
    @State var selectedRegion: Region?

    /// Whether to disable the `List` interactions. This is set to `true` during certain tasks.
    @State var disableInteractions: Bool = false

    /// An error to display as an alert.
    @State var taskError: Error?

    /// The currently editing region.
    @State var editingRegion: Region?
    @State var isShowingCustomRegionSheet: Bool = false

    var body: some View {
        List {
            Toggle("Automatically select region", isOn: $regionProvider.automaticallySelectRegion)
            Picker("", selection: $selectedRegion) {
                ForEach(filteredRegions, id: \.self) { region in
                    cell(for: region)
                        .tag(Optional(region))  // The tag type must match the selection type (an *optional* Region)
                }
            }
            .disabled(regionProvider.automaticallySelectRegion)
            .pickerStyle(.inline)
            .labelsHidden()         // Hide picker header (title)
        }
        // List modifiers
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .refreshable(action: doRefreshRegions)
        .disabled(disableInteractions)

        // Lifecycle-related modifiers
        .onAppear(perform: setCurrentRegionIfPresent)
        .onChange(of: regionProvider.automaticallySelectRegion) { [regionProvider] _ in
            // When the user selects to automatically select a region, update
            // selectedRegion with the new current region.
            self.selectedRegion = regionProvider.currentRegion
        }

        // Presentation-related modifiers
        .errorAlert(error: $taskError)
        .background {
            // TODO: I hate this. iOS 16 has NavigationStack, so use it when we drop iOS 15.
            NavigationLink(destination: RegionCustomForm(regionProvider: regionProvider, editingRegion: $editingRegion), isActive: $isShowingCustomRegionSheet) {
                EmptyView()
            }
        }

        // Supplementary views
        .safeAreaInset(edge: .top) {
            OnboardingHeaderView(imageSystemName: "globe", headerText: OBALoc("region_picker.title", value: "Choose Region", comment: "Title of the Region Picker Item, which lets the user choose a new region from the map."))
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                RegionPickerMap(mapRect: Binding(get: {
                    selectedRegion?.serviceRect
                }, set: { _ in }), mapHeight: 200)
                    .zIndex(-1) // Make the Map moving transition occur below the [Continue] button.

                TaskButton(action: doSetCurrentRegion) {
                    Text(Strings.continue)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .disabled(selectedRegion == nil || disableInteractions)
                .buttonStyle(.borderedProminent)

                regionOptions
            }
            .background(.background)
        }

        // Global
        .interactiveDismissDisabled(selectedRegion == nil || disableInteractions)
        .navigationBarHidden(true)
        .padding()
    }

    @ViewBuilder
    func cell(for region: Region) -> some View {
        Label {
            Text(region.name)
        } icon: {
            if region.isExperimental {
                Image(systemName: experimentalRegionSystemImageName)
                    .help(OBALoc(
                        "region_picker.experimental_region_help_text",
                        value: "Experimental region",
                        comment: "Help text displayed on an experimental region."
                    ))
            }

            if region.isActive == false {
                Image(systemName: inactiveRegionSystemImageName)
                    .help(OBALoc(
                        "region_picker.inactive_region_help_text",
                        value: "Inactive region",
                        comment: "Help text displayed on an inactive region."
                    ))
            }

            if let isCustom = region.isCustom, isCustom {
                Image(systemName: "doc.fill")
                    .help(OBALoc(
                        "region_picker.custom_region_help_text",
                        value: "Custom region",
                        comment: "Help text displayed on a custom (user-created) region."
                    ))
            }
        }
        .labelStyle(.titleAndIcon)
        .contextMenu {
            if let isCustom = region.isCustom, isCustom {
                Button {
                    self.editingRegion = region
                    self.isShowingCustomRegionSheet = true
                } label: {
                    Label(Strings.edit, systemImage: "pencil")
                }
                .tint(.accentColor)
            }
        }
    }

    /// `[More Options]` menu.
    var regionOptions: some View {
        Menu {
            Button {
                editingRegion = nil
                isShowingCustomRegionSheet = true
            } label: {
                Label(OBALoc("region_picker.new_custom_region_button", value: "New Custom Region", comment: "Title of a button that shows a region creation view controller."), systemImage: "doc.badge.plus")
            }

            Section {
                Toggle(isOn: $showInactiveRegions) {
                    Label(OBALoc("region_picker.show_inactive_regions_toggle", value: "Show Inactive", comment: "Title of a toggle that shows inactive regions."), systemImage: inactiveRegionSystemImageName)
                }

                Toggle(isOn: $showExperimentalRegions) {
                    Label(OBALoc("region_picker.show_experimental_regions_toggle", value: "Show Experimental", comment: "Title of a toggle that shows experimental (beta) regions."), systemImage: experimentalRegionSystemImageName)
                }
            }
        } label: {
            Text("More Options")
        }

    }

    func setCurrentRegionIfPresent() {
        if let currentRegion = regionProvider.currentRegion, currentRegion != self.selectedRegion {
            self.selectedRegion = currentRegion
        }
    }

    @Sendable
    private func doSetCurrentRegion() async {
        guard !disableInteractions, let selectedRegion else {
            return
        }

        disableInteractions = true
        defer {
            disableInteractions = false
        }

        // Set the current region, then dismiss the sheet if successful.
        do {
            try await regionProvider.setCurrentRegion(to: selectedRegion)
            await MainActor.run {
                dismiss()
            }
        } catch {
            taskError = error
        }
    }

    @Sendable
    private func doRefreshRegions() async {
        guard !disableInteractions else {
            return
        }

        disableInteractions = true
        defer {
            disableInteractions = false
        }

        // Do the task.
        do {
            try await regionProvider.refreshRegions()
            taskError = nil
        } catch {
            taskError = error
        }
    }
}

#if DEBUG
struct RegionPickerView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Hello, World!")
            .sheet(isPresented: .constant(true)) {
                NavigationView {
                    RegionPickerView(regionProvider: Previews_SampleRegionProvider())
                }
            }
            .previewDisplayName("As a sheet")

        RegionPickerView(regionProvider: Previews_SampleRegionProvider())
            .previewDisplayName("Standalone (for previewing variants)")
    }
}

#endif
