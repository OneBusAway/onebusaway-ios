//
//  RegionPickerView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/2/23.
//

import MapKit
import SwiftUI
import OBAKitCore

struct RegionPickerView: View {
    @Environment(\.dismiss) var dismiss
    var regionProvider: any RegionProvider

    /// The currently selected region.
    @State var selectedRegion: Region?

    /// Whether to disable the `List` interactions. This is set to `true` during certain tasks.
    @State var disableInteractions: Bool = false

    /// An error to display as an alert.
    @State var taskError: Error?

    /// The currently editing region.
    @State var editingRegion: Region?

    var body: some View {
        List {
            Picker("", selection: $selectedRegion) {
                ForEach(regionProvider.regions, id: \.self) { region in
                    Text(region.name)
                        .tag(Optional(region))  // The tag type must match the selection type (an *optional* Region)
                        .swipeActions(allowsFullSwipe: false) {
                            if let isCustom = region.isCustom, isCustom {
                                Button {
                                    self.editingRegion = region
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                        }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()         // Hide picker header (title)
        }
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .refreshable(action: doRefreshRegions)
        .disabled(disableInteractions)
        .onAppear(perform: setCurrentRegionIfPresent)
        .errorAlert(error: $taskError)
        .sheet(item: $editingRegion, content: { region in
            RegionCustomForm(regionProvider: regionProvider, editingRegion: region)
        })
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
            }
            .background(.background)
        }
        .padding()
    }

    func setCurrentRegionIfPresent() {
        if let currentRegion = regionProvider.currentRegion, currentRegion != self.selectedRegion {
            self.selectedRegion = currentRegion
        }
    }

    @Sendable
    private func doSetCurrentRegion() async {
        guard let selectedRegion else {
            return
        }

        // Set the current region, then dismiss the sheet if successful.
        await doTaskAndTrackResults {
            try await regionProvider.setCurrentRegion(to: selectedRegion)
        }

        if taskError == nil {
            dismiss()
        }
    }

    @Sendable
    private func doRefreshRegions() async {
        await doTaskAndTrackResults {
            try await regionProvider.refreshRegions()
        }
    }

    /// Runs the task only if `disableInteractions == false`. Task errors are put into `taskError`.
    @Sendable
    private func doTaskAndTrackResults(_ task: () async throws -> Void) async {
        // Disable user interaction while task is running.
        guard !disableInteractions else {
            return
        }

        disableInteractions = true
        defer {
            disableInteractions = false
        }

        // Do the task.
        do {
            try await task()
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
                RegionPickerView(regionProvider: Previews_SampleRegionProvider())
            }
            .previewDisplayName("As a sheet")

        RegionPickerView(regionProvider: Previews_SampleRegionProvider())
            .previewDisplayName("Standalone (for previewing variants)")
    }
}

#endif
