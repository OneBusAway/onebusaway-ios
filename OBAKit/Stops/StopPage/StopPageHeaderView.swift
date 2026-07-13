//
//  StopPageHeaderView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The full-bleed dark map header: an always-dark snapshot background under a
/// dark scrim, with the identity block bottom-left in white — the "last
/// updated" status line, stop name, the code/direction subtitle with inline
/// route chips (wrapping onto as many lines as needed, never truncated), and
/// the walk pill (the single visual source of walk time, §4.5). Tapping the
/// walk pill opens walking directions in an external maps app.
///
/// A plain-value view: it never touches `StopViewModel`. The map snapshot is
/// produced by a `snapshotLoader` closure supplied by the hosting VC, so the
/// view stays UIKit-free. Per the standing amendment, the snapshot size is
/// derived from the card's laid-out width (via `onGeometryChange`) rather than
/// `UIScreen.main`.
struct StopPageHeaderView: View {
    let stop: Stop
    let walkTime: WalkTimeInfo?
    /// The "Updated: …" line; empty hides it.
    let statusText: String
    let snapshotLoader: (CGSize) async -> UIImage?
    /// Opens walking directions to the stop (VC-owned; disambiguates between
    /// maps apps when more than one is available).
    let onWalkingDirections: () -> Void

    @State private var snapshot: UIImage?
    @State private var cardWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Minimum card height; the card grows beyond it when the identity block
    /// needs more room (wrapped chips, Dynamic Type). Scales with Dynamic Type
    /// so the stop name has room at larger text sizes (standing amendment).
    @ScaledMetric(relativeTo: .title2) private var cardHeight: CGFloat = 170

    private var subtitle: String {
        Formatters.formattedCodeAndDirection(stop: stop)
    }

    /// Sorted, de-duplicated route short names for the chips row. Mirrors
    /// `Formatters.formattedRoutes`' filtering (some agencies omit short names).
    private var routeChipNames: [String] {
        var seen = Set<String>()
        return stop.routes
            .map(\.shortName)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if !statusText.isEmpty {
                    HeaderStatusLine(statusText: statusText)
                }
                Text(stop.name)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    // Accessibility sizes get more lines so the full name still
                    // reads instead of clipping at the larger glyph sizes.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                // Subtitle + chips flow together and wrap onto as many lines as
                // the routes need — chips are never compressed or dropped.
                FlowLayout(hSpacing: 4, vSpacing: 4) {
                    Text(subtitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.trailing, 4)
                    ForEach(routeChipNames, id: \.self) { name in
                        routeChip(name)
                    }
                }
            }
            // One combined VoiceOver element for the identity text; the walk
            // button below stays separate so it remains individually
            // focusable and activatable.
            .accessibilityElement(children: .combine)
            if let walkTime {
                Button(action: onWalkingDirections) {
                    Label(walkChipText(walkTime), systemImage: "figure.walk")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(uiColor: ThemeColors.shared.departureOnTime), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(OBALoc("stop_page.header.walk_a11y_hint", value: "Opens walking directions to this stop.", comment: "VoiceOver hint on the header card's walk-time button."))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .bottomLeading)
        // The snapshot is a background so the identity block drives the card's
        // height — it can grow past `cardHeight` instead of clipping content.
        .background {
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true) // decorative map backdrop
                } else {
                    Color.black
                }
                // Dark scrim so the white identity block reads over any map
                // content, heaviest behind the text.
                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.45), .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            cardWidth = newWidth
        }
        .task(id: cardWidth) {
            // MapSnapshotter needs concrete dimensions; commit to the laid-out
            // card size once it's known. Keep the first snapshot on later
            // width changes (scaledToFill adapts) rather than re-rendering.
            guard cardWidth > 0, snapshot == nil else { return }
            snapshot = await snapshotLoader(CGSize(width: cardWidth, height: cardHeight))
        }
    }

    private func routeChip(_ name: String) -> some View {
        Text(name)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func walkChipText(_ info: WalkTimeInfo) -> String {
        let fmt = OBALoc(
            "stop_page.walk_chip_minutes_fmt",
            value: "%d min walk",
            comment: "Walk chip on the header card. %d is the walk time in minutes."
        )
        return String(format: fmt, info.walkMinutes)
    }
}
/// Skeleton stand-in for the header card, shown while `Stop` is still unknown
/// (a stop opened by bare ID — Recents, deep links — has no model until the
/// first fetch returns). Mirrors the real card's dark backdrop, minimum
/// height, and bottom-leading identity block so the page opens with its full
/// shape instead of decapitated.
struct StopPageHeaderPlaceholderView: View {
    @ScaledMetric(relativeTo: .title2) private var cardHeight: CGFloat = 170
    @ScaledMetric(relativeTo: .title2) private var nameLineHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) private var chipLineHeight: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            skeletonLine(width: 210, height: nameLineHeight)
            HStack(spacing: 4) {
                skeletonLine(width: 110, height: chipLineHeight)
                ForEach(0..<3, id: \.self) { _ in
                    skeletonLine(width: 30, height: chipLineHeight)
                }
            }
        }
        // Pulses the skeleton lines so the card reads as actively loading,
        // not stalled. Static under Reduce Motion, per the global constraints.
        .opacity(reduceMotion ? 1 : (pulsing ? 0.4 : 1))
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .bottomLeading)
        // A fixed dark gray rather than the real card's pre-snapshot black:
        // in dark mode the page background is black, and a black card there
        // has no visible edges — the skeleton lines just float in space.
        .background {
            ZStack {
                Color(white: 0.14)
                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.45), .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .clipped()
        .accessibilityHidden(true) // decorative; the loading row below announces progress
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.22))
            .frame(width: width, height: height)
    }
}

/// The "Updated: …" line atop the header's identity block, with a pulsing
/// on-time dot. The pulse is gated on Reduce Motion (static when reduced),
/// per the global constraints.
private struct HeaderStatusLine: View {
    let statusText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(uiColor: ThemeColors.shared.departureOnTime))
                .frame(width: 7, height: 7)
                .opacity(reduceMotion ? 1 : (pulsing ? 1 : 0.35))
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

/// Minimal leading-aligned wrapping layout: subviews flow left-to-right at
/// their ideal sizes and break onto new lines as needed, so chips wrap instead
/// of compressing or truncating. Shared by the header's subtitle + route chips
/// and the grouped card's upcoming-trip chips at accessibility sizes.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - hSpacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
