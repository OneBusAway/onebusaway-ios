//
//  MapSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import OBAKitCore
import SwiftUI
import UIKit

/// The Map sheet: basemap styles on top, stackable layer toggles below.
///
/// Presented from the basemap button in the map's control stack — a browse layer
/// buried in Settings is a discoverability failure, so this sheet is the single
/// canonical place riders turn layers on and off. Settings may mirror the same
/// UserDefaults keys, but it does not own them.
@MainActor final class MapSheetModel: ObservableObject {

    private let mapRegionManager: MapRegionManager
    private let mapViewModel: MapViewModel

    @Published private(set) var selectedBaseType: MapBaseType
    @Published private var stateVersion = 0

    private var cancellables = Set<AnyCancellable>()

    init(mapRegionManager: MapRegionManager, mapViewModel: MapViewModel) {
        self.mapRegionManager = mapRegionManager
        self.mapViewModel = mapViewModel
        self.selectedBaseType = mapViewModel.mapType

        NotificationCenter.default.publisher(for: .mapLayerAvailabilityDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.stateVersion += 1
            }
            .store(in: &cancellables)
    }

    // MARK: - Basemap

    func selectBaseType(_ type: MapBaseType) {
        selectedBaseType = type
        mapViewModel.setMapType(type)
    }

    // MARK: - Layers

    /// Layers to show for a group. Unsupported layers are hidden entirely —
    /// a row for something that can never load isn't a feature, it's a bug report.
    func visibleLayers(in group: MapLayerGroup) -> [MapLayer] {
        mapRegionManager.mapLayers.filter { $0.group == group && $0.availability != .unsupported }
    }

    func isEnabled(_ layer: MapLayer) -> Bool {
        mapRegionManager.isMapLayerEnabled(id: layer.id)
    }

    func setEnabled(_ enabled: Bool, layer: MapLayer) {
        mapRegionManager.setMapLayerEnabled(enabled, id: layer.id)
        stateVersion += 1
    }

    var showsResetButton: Bool {
        mapRegionManager.mapLayersDifferFromDefaults
    }

    func resetToDefaults() {
        mapRegionManager.resetMapLayersToDefaults()
        stateVersion += 1
    }
}

struct MapSheetView: View {
    @ObservedObject var model: MapSheetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                basemapSection

                layerSection(
                    title: OBALoc("map_sheet.transit_group", value: "Transit", comment: "Map sheet group header for transit layers"),
                    group: .transit
                )

                layerSection(
                    title: OBALoc("map_sheet.other_modes_group", value: "Other ways to get around", comment: "Map sheet group header for non-transit mobility layers"),
                    group: .otherModes
                )
            }
            .navigationTitle(OBALoc("map_sheet.title", value: "Map", comment: "Title of the Map sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Shown only when current state differs from the defaults.
                    if model.showsResetButton {
                        Button(OBALoc("map_sheet.reset", value: "Reset", comment: "Button restoring the default map layer configuration")) {
                            model.resetToDefaults()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
    }

    // MARK: - Basemap Tiles

    private var basemapSection: some View {
        Section {
            HStack(spacing: 12) {
                basemapTile(
                    .standard,
                    title: OBALoc("map_sheet.basemap_standard", value: "Standard", comment: "Basemap style: standard street map"),
                    systemImage: "map"
                )
                basemapTile(
                    .satellite,
                    title: OBALoc("map_sheet.basemap_satellite", value: "Satellite", comment: "Basemap style: satellite imagery"),
                    systemImage: "globe.americas.fill"
                )
                basemapTile(
                    .hybrid,
                    title: OBALoc("map_sheet.basemap_hybrid", value: "Hybrid", comment: "Basemap style: satellite imagery with labels"),
                    systemImage: "map.fill"
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func basemapTile(_ type: MapBaseType, title: String, systemImage: String) -> some View {
        let isSelected = model.selectedBaseType == type

        return Button {
            model.selectBaseType(type)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )

                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Layer Rows

    @ViewBuilder
    private func layerSection(title: String, group: MapLayerGroup) -> some View {
        let layers = model.visibleLayers(in: group)
        if !layers.isEmpty {
            Section(title) {
                ForEach(layers, id: \.id) { layer in
                    layerRow(layer)
                }
            }
        }
    }

    @ViewBuilder
    private func layerRow(_ layer: MapLayer) -> some View {
        // Unavailable rows are dimmed with a reason instead of hidden or left
        // toggleable: an enabled layer that cannot load would read as "there is
        // nothing here," which is a lie.
        let unavailableReason: String? = {
            if case .unavailable(let reason) = layer.availability { return reason }
            return nil
        }()

        HStack(spacing: 12) {
            Image(systemName: layer.iconName)
                .foregroundStyle(Color(uiColor: layer.tintColor))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(layer.title)
                if let unavailableReason {
                    Text(unavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle(layer.title, isOn: Binding(
                get: { model.isEnabled(layer) },
                set: { model.setEnabled($0, layer: layer) }
            ))
            .labelsHidden()
            .disabled(unavailableReason != nil)
        }
        .opacity(unavailableReason == nil ? 1 : 0.5)
    }
}
