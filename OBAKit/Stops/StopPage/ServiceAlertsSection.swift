//
//  ServiceAlertsSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Service alerts affecting this stop, rendered as one self-contained, neutral
/// card: a header row (an orange warning glyph, "N service alerts", a rotating
/// chevron) that toggles expansion, with the alert rows inside the
/// card when expanded. Each alert row pushes the existing alert-detail screen
/// via the hosting VC's `onSelect` callback.
///
/// Honors the `stopViewShowsServiceAlerts` preference (default collapsed):
/// tapping the header toggles and persists it. When expanded and there are more
/// than two alerts, it shows the first two plus a "Show all N" row.
struct ServiceAlertsSection: View {
    let alerts: [ServiceAlert]
    let onSelect: (ServiceAlert) -> Void

    /// A stored rider preference, so the key keeps its older name. Read and
    /// written through the app-group suite that `StopPageRootView` installs via
    /// `.defaultAppStorage`. Default `false` (collapsed).
    @AppStorage("stopViewShowsServiceAlerts") private var showsServiceAlerts = false

    /// Per-visit "show all" expansion for the >2 case (not persisted).
    @State private var showAllAlerts = false

    private var visibleAlerts: [ServiceAlert] {
        showAllAlerts ? alerts : Array(alerts.prefix(2))
    }

    var body: some View {
        // Neutral, with orange only on the glyph (#1754): severity is data, the
        // card around it isn't.
        StopPageTintedCard(tint: nil) {
            headerRow
            if showsServiceAlerts {
                ForEach(visibleAlerts) { alert in
                    StopPageCardDivider()
                    alertRow(alert)
                }
                if alerts.count > 2 && !showAllAlerts {
                    StopPageCardDivider()
                    showAllRow
                }
            }
        }
    }

    /// Always-visible card header; tapping toggles (and persists) expansion.
    private var headerRow: some View {
        Button {
            withAnimation(.snappy) {
                showsServiceAlerts.toggle()
                if !showsServiceAlerts { showAllAlerts = false }
            }
        } label: {
            HStack(spacing: 10) {
                // The glyph is decorative; the title carries the meaning. `warningText` is the
                // theme's orange tuned to stay legible in both appearances.
                Image(systemName: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: ThemeColors.shared.warningText))
                    .accessibilityHidden(true)
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsServiceAlerts ? 180 : 0))
                    // Decorative; the value below says expanded or collapsed.
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Disclosure state, so VoiceOver users know whether activating will
        // reveal or hide the alert rows.
        .accessibilityValue(showsServiceAlerts
            ? OBALoc("stop_page.service_alerts.a11y_expanded", value: "expanded", comment: "VoiceOver value of the service-alerts card header when the alert list is showing.")
            : OBALoc("stop_page.service_alerts.a11y_collapsed", value: "collapsed", comment: "VoiceOver value of the service-alerts card header when the alert list is hidden."))
        // Also a heading so it anchors VoiceOver's Headings rotor between the
        // stop title and the departures.
        .accessibilityAddTraits(.isHeader)
    }

    private var showAllRow: some View {
        Button {
            withAnimation { showAllAlerts = true }
        } label: {
            Text(CountPlural.format(OBALoc("stop_page.service_alerts.show_all_fmt", value: "Show all %d alerts", comment: "Row that expands the service alerts section to show every alert. %d is the total number of alerts. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), count: alerts.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: ThemeColors.shared.warningText))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerTitle: String {
        CountPlural.format(OBALoc("stop_page.service_alerts.summary_fmt", value: "%d service alerts", comment: "Collapsed summary row for the service alerts section. %d is the number of alerts. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), count: alerts.count)
    }

    private func alertRow(_ alert: ServiceAlert) -> some View {
        StopPageCardRow {
            onSelect(alert)
        } label: {
            Text(alert.title(forLocale: .current) ?? OBALoc("stop_page.service_alert_fallback", value: "Service alert", comment: "Fallback title for a service alert that has no summary text."))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
