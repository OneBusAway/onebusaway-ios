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

/// Service alerts affecting this stop, rendered as one self-contained,
/// orange-tinted card: a header row (gradient warning badge, title, count pill,
/// rotating chevron) that toggles expansion, with the alert rows inside the
/// card when expanded. Each alert row pushes the existing alert-detail screen
/// via the hosting VC's `onSelect` callback.
///
/// Honors the legacy `stopViewShowsServiceAlerts` preference (same UserDefaults
/// key, default collapsed): tapping the header toggles and persists it, matching
/// the legacy screen's collapsible section. When expanded and there are more
/// than two alerts, it shows the first two plus a "Show all N" row.
struct ServiceAlertsSection: View {
    let alerts: [ServiceAlert]
    let onSelect: (ServiceAlert) -> Void

    /// Legacy persisted preference; read/written through the app-group suite that
    /// `StopPageRootView` installs via `.defaultAppStorage`. Default `false`
    /// (collapsed) mirrors `StopViewController`, which registers no default for
    /// this key.
    @AppStorage("stopViewShowsServiceAlerts") private var showsServiceAlerts = false

    /// Per-visit "show all" expansion for the >2 case (not persisted).
    @State private var showAllAlerts = false

    /// The warning badge scales with Dynamic Type so its glyph never clips.
    @ScaledMetric(relativeTo: .subheadline) private var warningBadgeSize: CGFloat = 30

    private var visibleAlerts: [ServiceAlert] {
        showAllAlerts ? alerts : Array(alerts.prefix(2))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                headerRow
                if showsServiceAlerts {
                    ForEach(visibleAlerts) { alert in
                        Divider().padding(.leading, 14)
                        alertRow(alert)
                    }
                    if alerts.count > 2 && !showAllAlerts {
                        Divider().padding(.leading, 14)
                        showAllRow
                    }
                }
            }
            .background(cardShape.fill(Color.orange.opacity(0.08)))
            .overlay(cardShape.strokeBorder(Color.orange.opacity(0.22), lineWidth: 1))
            .clipShape(cardShape)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: warningBadgeSize, height: warningBadgeSize)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(Strings.serviceAlerts)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(alerts.count)")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsServiceAlerts ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(headerAccessibilityLabel)
        // Disclosure state, so VoiceOver users know whether activating will
        // reveal or hide the alert rows.
        .accessibilityValue(showsServiceAlerts
            ? OBALoc("stop_page.service_alerts.a11y_expanded", value: "expanded", comment: "VoiceOver value of the service-alerts card header when the alert list is showing.")
            : OBALoc("stop_page.service_alerts.a11y_collapsed", value: "collapsed", comment: "VoiceOver value of the service-alerts card header when the alert list is hidden."))
    }

    private var showAllRow: some View {
        Button {
            withAnimation { showAllAlerts = true }
        } label: {
            Text(String(format: OBALoc("stop_page.service_alerts.show_all_fmt", value: "Show all %d alerts", comment: "Row that expands the service alerts section to show every alert. %d is the total number of alerts. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), alerts.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerAccessibilityLabel: String {
        String(format: OBALoc("stop_page.service_alerts.summary_fmt", value: "%d service alerts", comment: "Collapsed summary row for the service alerts section. %d is the number of alerts. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), alerts.count)
    }

    private func alertRow(_ alert: ServiceAlert) -> some View {
        Button {
            onSelect(alert)
        } label: {
            HStack(spacing: 10) {
                Text(alert.title(forLocale: .current) ?? OBALoc("stop_page.service_alert_fallback", value: "Service alert", comment: "Fallback title for a service alert that has no summary text."))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true) // decorative; the alert title labels the button
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
