//
//  OnDemandServiceView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import SwiftUI

/// The on-demand service page: name and kind, a map of its zones, when it runs,
/// and how to book. Reached from a zone tap on the map, the stop page's
/// on-demand card, and the agency's service list.
///
/// A plain-value view: everything is computed by `OnDemandServiceSummary`
/// before construction, so the body is a straight rendering of its inputs.
struct OnDemandServiceView: View {
    let service: OnDemandService
    /// Always present. When the agency's time zone is unknown its booking line
    /// is `.unknown`, so the page shows hours and contact details with no
    /// deadline line.
    let summary: OnDemandServiceSummary
    let onOpenURL: (URL) -> Void
    /// Built once here: `showsMap` and the map body both read them.
    private let polygons: [MKPolygon]

    init(service: OnDemandService, summary: OnDemandServiceSummary, onOpenURL: @escaping (URL) -> Void) {
        self.service = service
        self.summary = summary
        self.onOpenURL = onOpenURL
        self.polygons = service.areas.flatMap(\.mkPolygons)
    }

    /// The map section renders only when at least one area has a ring
    /// MapKit can draw; a degenerate ring would leave an empty map.
    var showsMap: Bool {
        !polygons.isEmpty
    }

    var bookingLineText: String? {
        Self.bookingLineText(for: summary.bookingLine)
    }

    /// The booking rule's info page, falling back to the service's own URL.
    var infoURL: URL? {
        summary.infoURL ?? service.url
    }

    /// Whether the booking section has a contact row; with no deadline line
    /// either, the section is omitted rather than left as a bare header.
    var hasContactDetails: Bool {
        summary.phoneURL != nil || summary.bookingURL != nil || infoURL != nil
    }

    /// Wraps the presenter's formatted pieces in the localized sentence
    /// templates. `unknown` deliberately renders nothing (spec §6.2).
    static func bookingLineText(for line: OnDemandServiceSummary.BookingLine) -> String? {
        switch line {
        case .bookBy(let deadline, let travelDate):
            return String(format: Strings.onDemandBookByFormat, deadline, travelDate)
        case .opensAt(let opens):
            return String(format: Strings.onDemandBookingOpensFormat, opens)
        case .noNoticeRequired:
            return Strings.onDemandNoNoticeRequired
        case .closed:
            return Strings.onDemandBookingClosed
        case .unknown:
            return nil
        }
    }

    private var tint: Color {
        Color(service.route?.color ?? ThemeColors.shared.brand)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.name)
                        .font(.title2.weight(.semibold))
                    Text(Strings.onDemandKindTitle(service.serviceKind))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(tint)
                    if let description = service.serviceDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
            }

            if showsMap {
                Section {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(Array(polygons.enumerated()), id: \.offset) { _, polygon in
                            MapPolygon(polygon)
                                .foregroundStyle(tint.opacity(0.2))
                                .stroke(tint, lineWidth: 2)
                        }
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                    .accessibilityHidden(true)
                }
            }

            Section(Strings.onDemandWhenHeader) {
                if summary.windows.isEmpty {
                    Text(Strings.onDemandAllHours).foregroundStyle(.secondary)
                }
                ForEach(summary.windows, id: \.self) { window in
                    HStack {
                        Text(window.days).font(.body.weight(.medium))
                        Spacer()
                        Text(window.hours ?? Strings.onDemandAllHours).foregroundStyle(.secondary)
                    }
                }
            }

            if bookingLineText != nil || hasContactDetails {
                Section(Strings.onDemandBookingHeader) {
                    if let bookingLineText {
                        Label(bookingLineText, systemImage: "clock")
                    }
                    if let phone = summary.phoneNumber, let phoneURL = summary.phoneURL {
                        Button { onOpenURL(phoneURL) } label: {
                            Label(String(format: Strings.onDemandCallFormat, phone), systemImage: "phone.fill")
                        }
                    }
                    if let bookingURL = summary.bookingURL {
                        Button { onOpenURL(bookingURL) } label: {
                            Label(Strings.onDemandBookOnline, systemImage: "safari")
                        }
                    }
                    if let infoURL {
                        Button { onOpenURL(infoURL) } label: {
                            Label(Strings.onDemandMoreInfo, systemImage: "info.circle")
                        }
                    }
                }
            }

            if let message = summary.message {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// The union of the areas' bounding boxes, padded so the outline is not
    /// flush with the map edge.
    private var mapRegion: MKCoordinateRegion {
        let boxes = service.areas.filter(\.hasGeometry).map(\.bbox)
        guard let first = boxes.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
        }
        let minLat = boxes.map(\.minLatitude).min() ?? first.minLatitude
        let maxLat = boxes.map(\.maxLatitude).max() ?? first.maxLatitude
        let minLon = boxes.map(\.minLongitude).min() ?? first.minLongitude
        let maxLon = boxes.map(\.maxLongitude).max() ?? first.maxLongitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.2 + 0.01, longitudeDelta: (maxLon - minLon) * 1.2 + 0.01)
        )
    }
}
