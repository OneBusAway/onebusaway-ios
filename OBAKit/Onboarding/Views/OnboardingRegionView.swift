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

    /// The region the card shows and how the app arrived at it.
    private var selection: OnboardingRegionSelection? {
        OnboardingRegionSelection.resolve(
            chosen: selectedRegion,
            current: regionProvider.currentRegion,
            located: OnboardingRegionSelection.locatedRegion(in: regionProvider.allRegions, location: regionProvider.currentLocation))
    }

    private func shortList(excluding displayed: Region?) -> [Region] {
        var candidates = regionProvider.allRegions.filter { $0.id != displayed?.id }
        if let location = regionProvider.currentLocation {
            candidates.sort { $0.distanceFrom(location: location) < $1.distanceFrom(location: location) }
        }
        return Array(candidates.prefix(3))
    }

    var body: some View {
        // Hoisted once per render: resolving the selection is an O(n) scan over allRegions
        // and `shortList` re-filters it; the body references both repeatedly.
        let selection = self.selection
        let shortList = shortList(excluding: selection?.region)

        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.region.title", value: "Your region", comment: "Title of the region onboarding screen"),
            bodyText: bodyText(for: selection?.source),
            primaryTitle: Strings.continue,
            primaryDisabled: selection == nil,
            primaryAction: confirmSelection
        ) {
            VStack(spacing: 0) {
                if let selection {
                    selectedCard(for: selection)
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
                                    // Without this the row's tappable area collapses to the
                                    // glyphs of the region name: `.buttonStyle(.plain)` derives
                                    // the hit region from the label's content rather than from
                                    // the frame drawn around it, so most of the row ignored
                                    // taps. See https://github.com/OneBusAway/onebusaway-ios/issues/1315
                                    .contentShape(.rect)
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

    private func selectedCard(for selection: OnboardingRegionSelection) -> some View {
        VStack(spacing: 0) {
            // Live map preview, preferred over MKMapSnapshotter because snapshots
            // don't adapt to dark mode.
            RegionPickerMap(mapRect: .constant(selection.region.serviceRect), mapHeight: 108)
                .allowsHitTesting(false)
                .frame(height: 108)
                .clipped()
            cardFooter(for: selection)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func cardFooter(for selection: OnboardingRegionSelection) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow(for: selection.source))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
                Text(selection.region.name)
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

    /// The card's eyebrow. Each `Source` names how the region got onto the card, so the
    /// label can't claim detection for a region the rider's location never produced.
    private func eyebrow(for source: OnboardingRegionSelection.Source) -> String {
        switch source {
        case .detected:
            return OBALoc("onboarding.region.detected_label", value: "Detected near you", comment: "Label on the detected-region card")
        case .chosen:
            return OBALoc("onboarding.region.selected_label", value: "Your selection", comment: "Label on the region card when the rider chose the region from the list rather than it being detected from their location")
        case .preselected:
            return OBALoc("onboarding.region.current_label", value: "Current region", comment: "Label on the region card when the region was already selected by app configuration or an earlier launch rather than detected from the rider's location")
        }
    }

    /// The screen's body text. Detection is the only state where the app can claim it found
    /// the region; the others get the standing instruction, which stays true whether the
    /// rider picked the card's region or is about to replace it.
    private func bodyText(for source: OnboardingRegionSelection.Source?) -> String {
        switch source {
        case .detected:
            return OBALoc("onboarding.region.body", value: "We found the transit network closest to you.", comment: "Body of the region onboarding screen when the region was detected from the rider's location")
        case .chosen, .preselected, nil:
            return OBALoc("onboarding.region.body_choose", value: "Choose the transit network you ride.", comment: "Body of the region onboarding screen prompting the rider to choose a transit network")
        }
    }

    private func confirmSelection() {
        guard let region = selection?.region else { return }
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
