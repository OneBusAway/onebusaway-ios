//
//  MapLayerTileView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// A 62 pt layer tile: icon well, title, On/Off (or the unavailable reason).
/// On, it takes its group's tint; unavailable, it dims to 0.5.
struct MapLayerTileView: View {
    let tile: MapLayerTile
    let tint: Color
    let onTap: () -> Void

    private static let height: CGFloat = 62
    private static let cornerRadius: CGFloat = 16
    private static let wellSize: CGFloat = 34
    private static let offWell = Color(red: 0xe9 / 255.0, green: 0xe9 / 255.0, blue: 0xee / 255.0)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tile.isEnabled ? Color.white.opacity(0.22) : Self.offWell)
                    Image(systemName: tile.iconName).font(.body.weight(.semibold))
                }
                .frame(width: Self.wellSize, height: Self.wellSize)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(tile.subtitle).font(.caption).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .foregroundStyle(tile.isEnabled ? Color.white : Color.primary)
            .background(tile.isEnabled ? tint : Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!tile.isTapEnabled)
        .opacity(tile.unavailableReason == nil ? 1 : 0.5)
        // The visible subtitle swaps On/Off for the unavailable reason; VoiceOver
        // keeps the state and hears the reason as the hint.
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.isEnabled ? Strings.mapLayersStateOn : Strings.mapLayersStateOff)
        .accessibilityHint(tile.unavailableReason ?? "")
        .accessibilityAddTraits(tile.isEnabled ? .isSelected : [])
    }
}

/// The "Min. range" chips shown under the Rentals group.
struct RentalRangeChipRow: View {
    let presets: [RentalRangePreset]
    let selectedID: Int
    let onSelect: (Int) -> Void

    private static let minimumTapHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            Label(Strings.mapLayersMinRange, systemImage: "bolt")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            // Six rungs plus the label overflow a compact-width row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        chip(for: preset)
                    }
                }
            }
        }
    }

    private func chip(for preset: RentalRangePreset) -> some View {
        let isSelected = preset.id == selectedID
        return Button {
            onSelect(preset.id)
        } label: {
            Text(preset.title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color(uiColor: .rentalPurple) : Color(uiColor: .systemBackground), in: Capsule())
                .frame(minHeight: Self.minimumTapHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
