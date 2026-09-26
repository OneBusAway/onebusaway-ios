//
//  OnDemandZoneCardView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// The zone card's content (spec 3.3): the first inside match by the shared
/// sort, its meta line, its one primary action and how many others cover the point.
struct OnDemandZoneCardModel: Equatable {

    enum PrimaryAction: Equatable {
        case call(URL)
        case bookOnline(URL)
    }

    let match: OnDemandServiceMatch
    /// Every inside match in sort order; the footer opens the picker over these.
    let insideMatches: [OnDemandServiceMatch]
    let eyebrow: String
    let title: String
    let meta: String?
    let color: UIColor
    let primary: PrimaryAction?
    let moreCount: Int

    /// Nil unless at least one match contains the probe point.
    init?(insideMatches: [OnDemandServiceMatch], colors: [String: UIColor], copy: OnDemandCopy) {
        let inside = sortedSoonestUsable(insideMatches.filter(\.isInside))
        guard let first = inside.first else { return nil }
        match = first
        self.insideMatches = inside
        eyebrow = Strings.onDemandCardEyebrow
        title = first.service.name
        meta = copy.forService(first.service).cardMeta(first.availability)
        color = colors[first.id] ?? OnDemandServiceColors.baseColor(for: first.service)
        primary = Self.primaryAction(for: first.service)
        moreCount = inside.count - 1
    }

    /// The shared contact (ruling P3): a phone number wins, else a booking URL.
    /// Dials `telephoneURL`, the same URL the detail page's summary uses.
    static func primaryAction(for service: OnDemandService) -> PrimaryAction? {
        guard let bookingRule = service.contactBookingRule else { return nil }
        if let url = bookingRule.phoneNumber?.telephoneURL {
            return .call(url)
        }
        if let bookingURL = bookingRule.bookingURL {
            return .bookOnline(bookingURL)
        }
        return nil
    }
}

/// Status text with a leading "Open" / "Open now" in open-green semibold (spec 2.8).
struct OnDemandStatusText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    /// The localized lead-in words that mean "open" in `OnDemandCopy.statusText`:
    /// the whole string when there's no "until" clause, or the segment before
    /// the " · " that joins it to one. Derived from the format strings
    /// themselves (rather than hardcoded English) so a translation is
    /// followed; matched by exact prefix, not by `hasPrefix`, so "Opens
    /// tomorrow …" — a different status — is never mistaken for it.
    private static let openLeadIns: [String] = [
        Strings.onDemandStatusOpenNowUntilFormat.components(separatedBy: " · ").first,
        Strings.onDemandStatusOpen
    ].compactMap { $0 }

    var body: some View {
        if let leadIn = Self.openLeadIns.first(where: { text == $0 || text.hasPrefix("\($0) ·") }) {
            Text(leadIn).foregroundStyle(Color(uiColor: ThemeColors.shared.onDemandOpenGreen)).fontWeight(.semibold)
                + Text(text.dropFirst(leadIn.count))
        } else {
            Text(text)
        }
    }
}

struct OnDemandZoneCardView: View {
    let model: OnDemandZoneCardModel
    let locationCheck: OnDemandLocationCheck
    let actions: OnDemandDockActions

    private static let cornerRadius: CGFloat = 22
    private static let iconSize: CGFloat = 40
    private static let pillHeight: CGFloat = 40
    private static let detailsFill = Color(red: 0xee / 255.0, green: 0xf4 / 255.0, blue: 0xe6 / 255.0)

    private var accent: Color { Color(uiColor: ThemeColors.shared.brandAccent) }

    var body: some View {
        VStack(spacing: 12) {
            Button { actions.openDetail(model.match, locationCheck) } label: { headerRow }
                .buttonStyle(.plain)

            buttonRow

            if model.moreCount > 0 {
                Divider()
                Button {
                    actions.openPicker(OnDemandPickerRequest(matches: model.insideMatches, scope: .insideOnly, source: locationCheck.source, coordinate: locationCheck.coordinate))
                } label: {
                    HStack {
                        Text(OnDemandCopy.moreServices(model.moreCount))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(Color(uiColor: model.color))
                Image(systemName: "car.fill").foregroundStyle(.white)
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.eyebrow).font(.footnote.weight(.semibold)).foregroundStyle(accent)
                Text(model.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                if let meta = model.meta {
                    OnDemandStatusText(meta).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var buttonRow: some View {
        HStack(spacing: 10) {
            if let primary = model.primary {
                Button {
                    switch primary {
                    case .call(let url): actions.call(url)
                    case .bookOnline(let url): actions.openURL(url)
                    }
                } label: {
                    Label(primaryTitle(primary), systemImage: primaryIcon(primary))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Self.pillHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .layoutPriority(1.5)
            }

            Button { actions.openDetail(model.match, locationCheck) } label: {
                Text(Strings.onDemandCardDetails)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: Self.pillHeight)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .background(Self.detailsFill, in: Capsule())
        }
    }

    private func primaryTitle(_ action: OnDemandZoneCardModel.PrimaryAction) -> String {
        switch action {
        case .call: return Strings.onDemandCardCallToBook
        case .bookOnline: return Strings.onDemandBookOnline
        }
    }

    private func primaryIcon(_ action: OnDemandZoneCardModel.PrimaryAction) -> String {
        switch action {
        case .call: return "phone.fill"
        case .bookOnline: return "arrow.up.right.square"
        }
    }
}
