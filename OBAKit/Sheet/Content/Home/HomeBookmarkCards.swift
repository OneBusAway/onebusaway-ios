//
//  HomeBookmarkCards.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The home sheet's bookmarks, as a row of cards that scrolls sideways: each one
/// a bookmark's next departure, readable at the sheet's half height without a
/// tap. The Bookmarks tab has the full rows.
struct HomeBookmarkCards: View {
    let rows: [BookmarkRowViewModel]
    let onSelect: (BookmarkRowViewModel) -> Void
    let onTogglePin: (BookmarkRowViewModel) -> Void

    @Environment(\.obaFormatters) private var formatters

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(rows) { row in
                    Button {
                        onSelect(row)
                    } label: {
                        HomeBookmarkCard(row: row)
                    }
                    .buttonStyle(.plain)
                    // On the button, one element per card, with the same words the
                    // Bookmarks tab's rows speak, so a bookmark sounds the same
                    // wherever it is.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel(base: formatters.accessibilityLabel(for: row)))
                    .accessibilityValue(formatters.accessibilityValue(for: row) ?? "")
                    .accessibilityAddTraits(row.isTripBookmark ? [.isButton, .updatesFrequently] : .isButton)
                    .contextMenu {
                        // Pinning is reachable from the card it affects, not only
                        // from the Bookmarks tab: this row is where the result shows.
                        BookmarkPinButton(isPinned: row.isPinned) {
                            onTogglePin(row)
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        // The home sheet's pages carry a bottom content margin for the home
        // indicator, which every scroll view under them inherits: here it would
        // open a gap under the cards whenever the sheet reaches the screen's edge.
        .contentMargins(.bottom, 0, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// One bookmark in `HomeBookmarkCards`. A trip bookmark shows its route, name,
/// countdown and the departures after it; a stop bookmark, which has no one trip
/// to count down to, its name and routes.
struct HomeBookmarkCard: View {
    let row: BookmarkRowViewModel

    @Environment(\.obaFormatters) private var formatters
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 164
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 112

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A list row's fill: grey on the white the sheet has where it shows its
    /// glass, and the grouped row colour on its opaque grouped background.
    private var fill: Color {
        colorScheme.showsSheetGlass ? Color(.secondarySystemBackground) : Color(.secondarySystemGroupedBackground)
    }

    private var primary: ArrivalDeparture? { row.arrivalDepartures.first }

    /// The departures after the next, as bare minutes: "23, 38".
    private var laterMinutes: String? {
        let later = row.arrivalDepartures.dropFirst().prefix(2).map { max(0, $0.arrivalDepartureMinutes) }
        guard !later.isEmpty else { return nil }
        return later.map { $0.formatted() }.formatted(.list(type: .and, width: .narrow))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                badge
                Spacer(minLength: 0)
                if row.isPinned {
                    BookmarkPinIndicator()
                }
            }
            Text(row.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            footer
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var badge: some View {
        if row.isTripBookmark {
            RouteBadgeView(
                routeShortName: row.routeShortName ?? row.name,
                routeColor: Color(uiColor: primary?.route.color ?? ThemeColors.shared.brand),
                size: 32
            )
        } else {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Color(uiColor: ThemeColors.shared.brandAccent),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let primary {
            let status = DepartureStatus(arrivalDeparture: primary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CountdownView(
                    minutes: max(0, primary.arrivalDepartureMinutes),
                    isRealTime: status.isRealTime,
                    color: Color(uiColor: status.color)
                )
                if let laterMinutes {
                    Text(laterMinutes)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if row.isTripBookmark {
            Text(BookmarkCardView.noDeparturesMessage(hasLoadedArrivalData: row.hasLoadedArrivalData))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if let subtitle = row.routesSubtitle {
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
