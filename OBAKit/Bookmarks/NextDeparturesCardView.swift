//
//  NextDeparturesCardView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Next Departures card that Siri, Spotlight and Shortcuts show on iOS 26
/// (#1554): the bookmark, its route and headsign, and up to three departures,
/// or the sentence the dialog speaks when there are none to list.
///
/// The buttons come from the caller: in the snippet they are `Button(intent:)`
/// controls, which this view has no reason to know about.
struct NextDeparturesCardView<Actions: View>: View {
    let model: NextDeparturesCardModel
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bookmarkName = model.bookmarkName, let routeShortName = model.routeShortName {
                header(bookmarkName: bookmarkName, routeShortName: routeShortName)
            }

            if !model.rows.isEmpty {
                VStack(spacing: 8) {
                    ForEach(model.rows) { row in
                        departureRow(row)
                    }
                }
            }

            if let message = model.message {
                Text(message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                actions()
            }
        }
        .padding()
    }

    private func header(bookmarkName: String, routeShortName: String) -> some View {
        HStack(spacing: 12) {
            RouteBadgeView(
                routeShortName: routeShortName,
                routeColor: Color(uiColor: ThemeColors.shared.brand),
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmarkName)
                    .font(.headline)
                    .lineLimit(2)
                if let headsign = model.headsign {
                    Text(headsign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func departureRow(_ row: NextDeparturesCardModel.Row) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.timeText)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
            Spacer(minLength: 8)
            // In words as well as color, so color is never the only signal.
            Text(row.statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: row.status.color))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
