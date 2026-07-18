//
//  OnboardingRegionView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Region selection: an auto-detected card with a short list fallback.
/// "See all regions" pushes the existing full `RegionPickerView` (custom regions live there).
struct OnboardingRegionView<Provider: RegionProvider>: View {
    var progress: (index: Int, total: Int)?
    @ObservedObject var regionProvider: Provider
    var advance: () -> Void

    @State private var selectedRegion: Region?
    @State private var error: Error?
    @State private var isSettingRegion = false

    /// The already-selected region if one exists, else the nearest region to the user's location.
    private var detectedRegion: Region? {
        if let current = regionProvider.currentRegion { return current }
        guard let location = regionProvider.currentLocation else { return nil }
        return regionProvider.allRegions.min {
            $0.distanceFrom(location: location) < $1.distanceFrom(location: location)
        }
    }

    private func shortList(excluding resolved: Region?) -> [Region] {
        var candidates = regionProvider.allRegions.filter { $0.id != resolved?.id }
        if let location = regionProvider.currentLocation {
            candidates.sort { $0.distanceFrom(location: location) < $1.distanceFrom(location: location) }
        }
        return Array(candidates.prefix(3))
    }

    var body: some View {
        // Hoisted once per render: `detectedRegion` is an O(n) distance scan and
        // `shortList` re-filters allRegions; the body references them repeatedly.
        let detected = detectedRegion
        let resolved = selectedRegion ?? detected
        let shortList = shortList(excluding: resolved)

        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.region.title", value: "Your region", comment: "Title of the region onboarding screen"),
            bodyText: detected == nil
                ? OBALoc("onboarding.region.body_no_location", value: "Choose the transit network you ride.", comment: "Body of the region onboarding screen when no location is available")
                : OBALoc("onboarding.region.body", value: "We found the transit network closest to you.", comment: "Body of the region onboarding screen"),
            primaryTitle: Strings.continue,
            primaryDisabled: resolved == nil,
            primaryAction: confirmSelection
        ) {
            VStack(spacing: 0) {
                if let region = resolved {
                    selectedCard(for: region)
                        .padding(.top, 22)
                }

                if !shortList.isEmpty {
                    Text(OBALoc("onboarding.region.other_header", value: "Or choose another", comment: "Header above the alternate-regions list"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(shortList.enumerated()), id: \.element.id) { index, region in
                            Button {
                                selectedRegion = region
                            } label: {
                                Text(region.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.plain)
                            if index != shortList.count - 1 { Divider() }
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                NavigationLink {
                    RegionPickerView(regionProvider: regionProvider, dismissBlock: advance)
                } label: {
                    Text(OBALoc("onboarding.region.see_all_button", value: "See all regions", comment: "Link to the full region picker"))
                        .font(.headline)
                }
                .padding(.top, 20)
            }
        }
        .task {
            do {
                try await regionProvider.refreshRegions()
            } catch {
                Logger.error("Onboarding region refresh failed: \(error)")
                self.error = error
            }
        }
        .disabled(isSettingRegion)
        .errorAlert(error: $error)
    }

    private func selectedCard(for region: Region) -> some View {
        VStack(spacing: 0) {
            // Live map preview, preferred over MKMapSnapshotter because snapshots
            // don't adapt to dark mode.
            RegionPickerMap(mapRect: .constant(region.serviceRect), mapHeight: 108)
                .allowsHitTesting(false)
                .frame(height: 108)
                .clipped()
            cardFooter(for: region)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func cardFooter(for region: Region) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(OBALoc("onboarding.region.detected_label", value: "Detected near you", comment: "Label on the detected-region card"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                Text(region.name)
                    .font(.title3.weight(.bold))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
    }

    private func confirmSelection() {
        guard let region = selectedRegion ?? detectedRegion else { return }
        isSettingRegion = true
        Task {
            defer { isSettingRegion = false }
            do {
                try await regionProvider.setCurrentRegion(to: region)
                advance()
            } catch {
                Logger.error("Onboarding region selection failed: \(error)")
                self.error = error
            }
        }
    }
}
