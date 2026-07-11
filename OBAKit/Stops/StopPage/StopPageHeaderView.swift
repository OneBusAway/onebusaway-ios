//
//  StopPageHeaderView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// The inset map-card header: snapshot background, stop identity, and the
/// walk chip — the single visual source of walk time (§4.5). Tap toggles the
/// routes-served line (parity with the old header).
///
/// A plain-value view: it never touches `StopViewModel`. The map snapshot is
/// produced by a `snapshotLoader` closure supplied by the hosting VC, so the
/// view stays UIKit-free. Per the standing amendment, the snapshot size is
/// derived from the card's laid-out width (via `onGeometryChange`) rather than
/// `UIScreen.main`.
struct StopPageHeaderView: View {
    let stop: Stop
    let walkTime: WalkTimeInfo?
    let snapshotLoader: (CGSize) async -> UIImage?

    @State private var snapshot: UIImage?
    @State private var showsRoutes = false
    @State private var cardWidth: CGFloat = 0

    /// Grows the card with Dynamic Type so the stop name has room at larger
    /// text sizes (standing amendment).
    @ScaledMetric(relativeTo: .title2) private var cardHeight: CGFloat = 150

    /// A single shared formatter; distances are formatted for display only.
    private static let distanceFormatter = MKDistanceFormatter()

    private var subtitle: String {
        Formatters.formattedCodeAndDirection(stop: stop)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemGroupedBackground)
                }
            }
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground).opacity(0.92),
                    Color(uiColor: .systemBackground).opacity(0.4),
                    .clear
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.title2.weight(.heavy))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                if showsRoutes, let routes = Formatters.formattedRoutes(stop.routes) {
                    Text(routes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .frame(height: cardHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let walkTime {
                Label(walkChipText(walkTime), systemImage: "figure.walk")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(uiColor: ThemeColors.shared.departureOnTime), in: Capsule())
                    .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showsRoutes.toggle() } }
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
        .accessibilityElement(children: .combine)
    }

    private func walkChipText(_ info: WalkTimeInfo) -> String {
        let distance = Self.distanceFormatter.string(fromDistance: info.distance)
        let fmt = OBALoc(
            "stop_page.walk_chip_fmt",
            value: "%d min walk · %@",
            comment: "Walk chip on the header card. %d minutes, %@ formatted distance."
        )
        return String(format: fmt, info.walkMinutes, distance)
    }
}
