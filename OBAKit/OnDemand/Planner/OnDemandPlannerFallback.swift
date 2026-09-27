//
//  OnDemandPlannerFallback.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import OBAKitCore
import SwiftUI
import UIKit

/// Spec 3.8: the services that can carry a trip between two probed points.
struct OnDemandPlannerResult: Equatable {
    let qualifying: [OnDemandServiceMatch]
    /// Services inside at either end that did not qualify (eligibility, one end, wrong direction).
    let hiddenCount: Int
    /// The inside-only list at the origin, for the "Show all" link.
    let originInsideMatches: [OnDemandServiceMatch]
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D

    static func == (lhs: OnDemandPlannerResult, rhs: OnDemandPlannerResult) -> Bool {
        lhs.qualifying == rhs.qualifying && lhs.hiddenCount == rhs.hiddenCount
            && lhs.origin.latitude == rhs.origin.latitude && lhs.origin.longitude == rhs.origin.longitude
            && lhs.destination.latitude == rhs.destination.latitude && lhs.destination.longitude == rhs.destination.longitude
    }
}

enum OnDemandPlannerQualifier {

    /// The ids of the match's areas that contain its probe point (server distance 0).
    static func insideAreaIDs(of match: OnDemandServiceMatch) -> Set<String> {
        Set(match.service.areas.filter { $0.distanceToArea == 0 }.map(\.id))
    }

    /// A service qualifies when it contains both points, is not tier 4, and
    /// some rule runs from an origin-containing area to a destination-containing area.
    static func result(
        origin: [OnDemandServiceMatch],
        destination: [OnDemandServiceMatch],
        originCoordinate: CLLocationCoordinate2D,
        destinationCoordinate: CLLocationCoordinate2D
    ) -> OnDemandPlannerResult {
        let originInside = sortedSoonestUsable(origin.filter(\.isInside))
        let destinationByID = Dictionary(destination.filter(\.isInside).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let qualifying = originInside.filter { originMatch in
            guard let destinationMatch = destinationByID[originMatch.id] else { return false }
            guard originMatch.availability.usabilityTier != OnDemandAvailability.eligibilityTier else { return false }
            let fromIDs = insideAreaIDs(of: originMatch)
            let toIDs = insideAreaIDs(of: destinationMatch)
            return originMatch.service.rules.contains { rule in
                !Set(rule.fromIDs).isDisjoint(with: fromIDs) && !Set(rule.toIDs).isDisjoint(with: toIDs)
            }
        }

        let consideredIDs = Set(originInside.map(\.id)).union(destinationByID.keys)
        return OnDemandPlannerResult(
            qualifying: qualifying,
            hiddenCount: consideredIDs.count - qualifying.count,
            originInsideMatches: originInside,
            origin: originCoordinate,
            destination: destinationCoordinate
        )
    }
}

/// One planner card: the screen-1 style with "Serves both locations" above the status line.
struct OnDemandPlannerCardModel: Equatable {
    let match: OnDemandServiceMatch
    let title: String
    let meta: String?
    let color: UIColor
    let primary: OnDemandZoneCardModel.PrimaryAction?

    init(match: OnDemandServiceMatch, colors: [String: UIColor], copy: OnDemandCopy) {
        self.match = match
        title = match.service.name
        meta = copy.forService(match.service).cardMeta(match.availability)
        color = OnDemandServiceColors.color(for: match, in: colors)
        primary = OnDemandZoneCardModel.primaryAction(for: match.service)
    }
}

struct OnDemandPlannerFallbackView: View {
    let result: OnDemandPlannerResult
    let copy: OnDemandCopy
    let colors: [String: UIColor]
    let actions: OnDemandDockActions

    /// The mock's pill height; the tappable area is grown to the 44 pt floor (Task 9 ruling).
    private static let pillHeight: CGFloat = 40
    private static let cornerRadius: CGFloat = 22
    /// A second card pushed the card into a scrolling fallback tall enough to
    /// cut off the first service's Call button; the rest are one tap away
    /// behind the "N more services serve both locations" row.
    static let maximumVisibleServices = 1

    static func visibleServices(in result: OnDemandPlannerResult) -> [OnDemandServiceMatch] {
        Array(result.qualifying.prefix(maximumVisibleServices))
    }

    /// Qualifying services without a card of their own.
    static func moreServingBothCount(in result: OnDemandPlannerResult) -> Int {
        max(result.qualifying.count - maximumVisibleServices, 0)
    }

    /// Every qualifying service, so the picker lists the carded one too.
    static func moreServingBothRequest(for result: OnDemandPlannerResult) -> OnDemandPickerRequest {
        OnDemandPickerRequest(matches: result.qualifying, scope: .insideOnly, source: .point(label: nil), coordinate: result.origin)
    }

    private var accent: Color { Color(uiColor: ThemeColors.shared.brandAccent) }

    private var locationCheck: OnDemandLocationCheck {
        OnDemandLocationCheck(source: .point(label: nil), isInside: true, locality: nil, coordinate: result.origin)
    }

    /// Scrolls inside the card when the space above the planner panel is
    /// shorter than the content (large text, a short screen).
    var body: some View {
        ViewThatFits(in: .vertical) {
            sections
            ScrollView { sections }
        }
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.onDemandPlannerSection).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)

            if result.qualifying.isEmpty && result.hiddenCount == 0 {
                Text(Strings.onDemandPlannerEmpty).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Self.visibleServices(in: result)) { match in
                    card(OnDemandPlannerCardModel(match: match, colors: colors, copy: copy))
                }
                moreServingBothRow
                Text(Strings.onDemandPlannerStatusNow).font(.caption).foregroundStyle(.secondary)
                // Stacked: side by side, the caption and the link each wrap to several lines.
                VStack(alignment: .leading, spacing: 0) {
                    Text(Strings.onDemandPlannerCaption).font(.caption).foregroundStyle(.secondary)
                    Button(Strings.onDemandPlannerShowAll) {
                        actions.openPicker(OnDemandPickerRequest(matches: result.originInsideMatches, scope: .insideOnly, source: .point(label: nil), coordinate: result.origin))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(minHeight: OnDemandZoneCardView.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var moreServingBothRow: some View {
        let moreCount = Self.moreServingBothCount(in: result)
        if moreCount > 0 {
            Button {
                actions.openPicker(Self.moreServingBothRequest(for: result))
            } label: {
                HStack {
                    Text(OnDemandCopy.moreServingBoth(moreCount)).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
                .foregroundStyle(accent)
                .frame(minHeight: OnDemandZoneCardView.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func card(_ model: OnDemandPlannerCardModel) -> some View {
        VStack(spacing: 10) {
            Button { actions.openDetail(model.match, locationCheck) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color(uiColor: model.color))
                        Image(systemName: "car.fill").foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title).font(.headline).lineLimit(2)
                        Text(Strings.onDemandPlannerServesBoth).font(.subheadline).foregroundStyle(.secondary)
                        if let meta = model.meta {
                            OnDemandStatusText(meta).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)

            if let primary = model.primary {
                Button {
                    switch primary {
                    case .call(let url): actions.call(url)
                    case .bookOnline(let url): actions.openURL(url)
                    }
                } label: {
                    Group {
                        switch primary {
                        case .call: Label(Strings.onDemandCardCallToBook, systemImage: "phone.fill")
                        case .bookOnline: Label(Strings.onDemandBookOnline, systemImage: "arrow.up.right.square")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Self.pillHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .frame(minHeight: OnDemandZoneCardView.minimumTouchTarget)
                .contentShape(Rectangle())
            }
        }
    }
}
