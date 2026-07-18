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

    /// Nearest region to the user, or their already-auto-selected region.
    private var detectedRegion: Region? {
        if let current = regionProvider.currentRegion { return current }
        guard let location = regionProvider.currentLocation else { return nil }
        return regionProvider.allRegions.min {
            $0.distanceFrom(location: location) < $1.distanceFrom(location: location)
        }
    }

    private var shortList: [Region] {
        regionProvider.allRegions
            .filter { $0.id != (selectedRegion ?? detectedRegion)?.id }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.region.title", value: "Your region", comment: "Title of the region onboarding screen"),
            bodyText: detectedRegion == nil
                ? OBALoc("onboarding.region.body_no_location", value: "Choose the transit network you ride.", comment: "Body of the region onboarding screen when no location is available")
                : OBALoc("onboarding.region.body", value: "We found the transit network closest to you.", comment: "Body of the region onboarding screen"),
            primaryTitle: OBALoc("onboarding.region.primary_button", value: "Continue", comment: "Primary button on the region onboarding screen"),
            primaryAction: confirmSelection
        ) {
            VStack(spacing: 0) {
                if let region = selectedRegion ?? detectedRegion {
                    selectedCard(for: region)
                        .padding(.top, 22)
                }

                if !shortList.isEmpty {
                    Text(OBALoc("onboarding.region.other_header", value: "Or choose another", comment: "Header above the alternate-regions list").uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(shortList, id: \.id) { region in
                            Button {
                                selectedRegion = region
                            } label: {
                                Text(region.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.plain)
                            if region.id != shortList.last?.id { Divider() }
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
            try? await regionProvider.refreshRegions()
        }
        .disabled(isSettingRegion)
        .errorAlert(error: $error)
    }

    private func selectedCard(for region: Region) -> some View {
        VStack(spacing: 0) {
            // Live map preview (spec: preferred over MKMapSnapshotter — adapts to dark
            // mode automatically and can draw the service-area overlay).
            RegionPickerMap(mapRect: .constant(region.serviceRect), mapHeight: 108)
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
                Text(OBALoc("onboarding.region.detected_label", value: "Detected near you", comment: "Label on the detected-region card").uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(region.name)
                    .font(.title3.weight(.bold))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding(16)
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
                self.error = error
            }
        }
    }
}
