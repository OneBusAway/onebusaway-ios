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

/// The on-demand service page (spec 3.6): header card with tags, status or
/// promoted deadline and the primary contact; the location row; the map;
/// Where, When, How to book; and the booking messages.
///
/// A plain-value view: everything is computed before construction, so the
/// body is a straight rendering of its inputs.
struct OnDemandServiceView: View {

    enum PrimaryContact: Equatable {
        case call(phone: String, url: URL)
        case bookOnline(URL)
    }

    struct WhereRows: Equatable {
        let serviceArea: String
        let dropOff: String?
    }

    struct WhenRow: Equatable {
        let days: String
        let hours: String?
    }

    let service: OnDemandService
    let summary: OnDemandServiceSummary
    let availability: OnDemandAvailability
    let locationCheck: OnDemandLocationCheck?
    let onOpenURL: (URL) -> Void

    private let polygons: [MKPolygon]
    private let copy: OnDemandCopy
    private let today: ServiceDate
    private let shortWeekdaySymbols: [String]

    private static let tagFill = Color(red: 0xe9 / 255.0, green: 0xf1 / 255.0, blue: 0xdd / 255.0)
    private static let warnFill = Color(red: 0xfb / 255.0, green: 0xef / 255.0, blue: 0xd5 / 255.0)
    private static let warnText = Color(red: 0x8a / 255.0, green: 0x5a / 255.0, blue: 0x00 / 255.0)
    private static let thumbnailHeight: CGFloat = 210

    init(
        service: OnDemandService,
        summary: OnDemandServiceSummary,
        availability: OnDemandAvailability,
        locationCheck: OnDemandLocationCheck?,
        now: Date,
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.service = service
        self.summary = summary
        self.availability = availability
        self.locationCheck = locationCheck
        self.onOpenURL = onOpenURL
        polygons = service.areas.flatMap(\.mkPolygons)
        let timeZone = service.timeZone ?? .current
        copy = OnDemandCopy(timeZone: timeZone, now: now)
        today = BookingDeadlineEvaluator(timeZone: timeZone, calendars: service.calendars).serviceDate(for: now)
        let symbols = DateFormatter()
        symbols.locale = .current
        shortWeekdaySymbols = symbols.shortWeekdaySymbols ?? Weekday.allCases.map(\.rawValue)
    }

    // MARK: - Derived facts

    var showsMap: Bool { !polygons.isEmpty }

    var bookingLineText: String? { Self.bookingLineText(for: summary.bookingLine) }

    var tags: [OnDemandAvailability.Tag] { availability.tags }

    /// Tiers 1 and 2, and a closed tier 5; nothing for unknown (item 1).
    var statusLineText: String? {
        switch availability.usabilityTier {
        case OnDemandAvailability.openNowTier, OnDemandAvailability.sameDayTier:
            return copy.statusText(availability.status, style: .detail)
        case OnDemandAvailability.unknownTier where availability.status == .closed:
            return Strings.onDemandStatusClosed
        default:
            return nil
        }
    }

    /// The promoted fact for advance services only (item 2).
    var promotedDeadlineText: String? {
        availability.usabilityTier == OnDemandAvailability.advanceTier ? bookingLineText : nil
    }

    var primaryContact: PrimaryContact? {
        if let phone = summary.phoneNumber, let url = summary.phoneURL {
            return .call(phone: phone, url: url)
        }
        if let bookingURL = summary.bookingURL {
            return .bookOnline(bookingURL)
        }
        return nil
    }

    var locationRowText: String? {
        guard let locationCheck else { return nil }
        switch (locationCheck.source, locationCheck.isInside) {
        case (.rider, true): return Strings.onDemandDetailLocationInside
        case (.rider, false): return Strings.onDemandDetailLocationOutside
        case (.mapCenter, true): return Strings.onDemandDetailCenterInside
        case (.mapCenter, false): return Strings.onDemandDetailCenterOutside
        case (.point, true): return Strings.onDemandDetailPointInside
        case (.point, false): return Strings.onDemandDetailPointOutside
        }
    }

    var locationRowSubtext: String? {
        guard let locationCheck, locationCheck.isInside, let locality = locationCheck.locality else { return nil }
        return String(format: Strings.onDemandDetailLocationSubFormat, locality)
    }

    /// Item 5: only for more than one area or a rule whose destinations differ.
    var whereRows: WhereRows? {
        let hasDistinctDropOff = service.rules.contains { Set($0.toIDs) != Set($0.fromIDs) }
        guard service.areas.count > 1 || hasDistinctDropOff else { return nil }

        let fromIDs = Set(service.rules.flatMap(\.fromIDs))
        var serviceArea = areaNames(for: fromIDs)
        if let locationCheck, locationCheck.source == .rider, locationCheck.isInside {
            serviceArea = String(format: Strings.onDemandDetailIncludesLocationFormat, serviceArea)
        }
        let dropOff = hasDistinctDropOff ? areaNames(for: Set(service.rules.flatMap(\.toIDs))) : nil
        return WhereRows(serviceArea: serviceArea, dropOff: dropOff)
    }

    /// Names resolved against areas, then location groups; unnamed ones fall back to a count.
    private func areaNames(for ids: Set<String>) -> String {
        let areas = service.areas.filter { ids.contains($0.id) }
        let groups = service.locationGroups.filter { ids.contains($0.id) }
        let names = areas.compactMap(\.name) + groups.compactMap(\.name)
        guard names.isEmpty else { return names.joined(separator: ", ") }
        return OnDemandCopy.zoneCount(max(areas.count + groups.count, ids.count))
    }

    /// Item 6: windows with identical hours merged into weekday ranges.
    var whenRows: [WhenRow] {
        var order: [String?] = []
        var weekdaysByHours: [String?: Set<Weekday>] = [:]
        for window in summary.windows {
            if weekdaysByHours[window.hours] == nil { order.append(window.hours) }
            weekdaysByHours[window.hours, default: []].formUnion(window.weekdays)
        }
        return order.map { hours in
            WhenRow(days: OnDemandServiceSummary.daysText(Array(weekdaysByHours[hours] ?? []), shortWeekdaySymbols: shortWeekdaySymbols), hours: hours)
        }
    }

    /// Weekdays absent from every calendar still in force, as one range string.
    var noServiceDays: String? {
        let inForce = service.calendars.filter { calendar in
            guard let endDate = calendar.endDate else { return true }
            return endDate >= today
        }
        let served = Set(inForce.flatMap(\.days))
        let missing = Weekday.allCases.filter { !served.contains($0) }
        guard !missing.isEmpty, missing.count < Weekday.allCases.count else { return nil }
        return OnDemandServiceSummary.daysText(missing, shortWeekdaySymbols: shortWeekdaySymbols)
    }

    /// The booking rule's info page, else the eligibility page; hidden when it
    /// would open the same page as "Open Agency Website" (item 7).
    var infoURL: URL? {
        let candidate = summary.infoURL ?? service.eligibility?.infoURL
        guard let candidate, candidate != service.url else { return nil }
        return candidate
    }

    var hasContactDetails: Bool {
        primaryContact != nil || service.url != nil || infoURL != nil
    }

    /// Item 8: the contact booking rule's messages, verbatim — the same rule
    /// the primary pill dials, so the footnote describes that booking.
    var footnotes: [String] {
        guard let bookingRule = service.contactBookingRule else { return [] }
        return [bookingRule.message, bookingRule.pickupMessage, bookingRule.dropOffMessage].compactMap { $0 }
    }

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

    private var accent: Color { Color(uiColor: ThemeColors.shared.brandAccent) }

    // MARK: - Body

    var body: some View {
        List {
            headerSection
            promotedDeadlineSection
            locationSection
            mapSection
            whereSection
            whenSection
            bookingSection
            footnoteSection
        }
        .listStyle(.insetGrouped)
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(service.name).font(.title.weight(.bold))
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                            tagView(tag)
                        }
                    }
                }
                if let description = service.serviceDescription {
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                }
                if let statusLineText {
                    OnDemandStatusText(statusLineText).font(.subheadline)
                }
                if let primaryContact {
                    primaryButton(primaryContact)
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    private func tagView(_ tag: OnDemandAvailability.Tag) -> some View {
        let isWarning = tag == .eligibilityRequired
        return Text(copy.tagText(tag))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isWarning ? Self.warnText : accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isWarning ? Self.warnFill : Self.tagFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func primaryButton(_ contact: PrimaryContact) -> some View {
        Button {
            switch contact {
            case .call(_, let url): onOpenURL(url)
            case .bookOnline(let url): onOpenURL(url)
            }
        } label: {
            Group {
                switch contact {
                case .call(let phone, _): Label(String(format: Strings.onDemandCallFormat, phone), systemImage: "phone.fill")
                case .bookOnline: Label(Strings.onDemandBookOnline, systemImage: "arrow.up.right.square")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
    }

    @ViewBuilder
    private var promotedDeadlineSection: some View {
        if let promotedDeadlineText {
            Section {
                Label(promotedDeadlineText, systemImage: "clock")
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        if let locationRowText, let locationCheck {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locationRowText).font(.callout.weight(.semibold))
                        if let locationRowSubtext {
                            Text(locationRowSubtext).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: locationCheck.isInside ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(locationCheck.isInside ? Color(uiColor: .systemGreen) : Color(uiColor: ThemeColors.shared.onDemandOutside))
                }
            }
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        if showsMap {
            Section {
                Map(initialPosition: .region(mapRegion)) {
                    ForEach(Array(polygons.enumerated()), id: \.offset) { _, polygon in
                        MapPolygon(polygon)
                            .foregroundStyle(tint.opacity(OnDemandZoneStyle.regionFillAlpha))
                            .stroke(tint, lineWidth: OnDemandZoneStyle.regionLineWidth)
                    }
                    if let locationCheck {
                        Annotation("", coordinate: locationCheck.coordinate) {
                            probeMarker(for: locationCheck.source)
                        }
                    }
                }
                .frame(height: Self.thumbnailHeight)
                .listRowInsets(EdgeInsets())
                .accessibilityHidden(true)
            }
        }
    }

    /// The same dot the location row describes: blue for the rider, gray for
    /// the map centre, a pin glyph for a chosen point.
    @ViewBuilder
    private func probeMarker(for source: ProbeSource) -> some View {
        switch source {
        case .rider:
            Circle().fill(Color(uiColor: .systemBlue)).frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        case .mapCenter:
            Circle().fill(Color(uiColor: ThemeColors.shared.onDemandOutside)).frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        case .point:
            Image(systemName: "mappin.and.ellipse").font(.title3).foregroundStyle(Color(uiColor: .systemRed))
        }
    }

    @ViewBuilder
    private var whereSection: some View {
        if let whereRows {
            Section(Strings.onDemandDetailWhereHeader) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Strings.onDemandDetailServiceArea)
                        Text(whereRows.serviceArea).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    let inside = locationCheck?.isInside == true
                    Image(systemName: inside ? "checkmark.circle.fill" : "mappin.and.ellipse")
                        .foregroundStyle(inside ? Color(uiColor: .systemGreen) : .secondary)
                }
                if let dropOff = whereRows.dropOff {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Strings.onDemandDetailDropOff)
                            Text(dropOff).font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var whenSection: some View {
        Section(Strings.onDemandWhenHeader) {
            if whenRows.isEmpty {
                Text(Strings.onDemandAllHours).foregroundStyle(.secondary)
            }
            ForEach(Array(whenRows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.days).font(.body.weight(.medium))
                    Spacer()
                    Text(row.hours ?? Strings.onDemandAllHours).foregroundStyle(.secondary)
                }
            }
            if let noServiceDays {
                HStack {
                    Text(noServiceDays).foregroundStyle(.secondary)
                    Spacer()
                    Text(Strings.onDemandDetailNoService).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var bookingSection: some View {
        if bookingLineText != nil || service.url != nil || infoURL != nil {
            Section(Strings.onDemandBookingHeader) {
                if let bookingLineText {
                    Label(bookingLineText, systemImage: "clock")
                }
                if let url = service.url {
                    Button { onOpenURL(url) } label: {
                        Label(Strings.onDemandDetailOpenAgencyWebsite, systemImage: "arrow.up.right.square")
                    }
                }
                if let infoURL {
                    Button { onOpenURL(infoURL) } label: {
                        Label(Strings.onDemandMoreInfo, systemImage: "info.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footnoteSection: some View {
        if !footnotes.isEmpty {
            Section {
                ForEach(Array(footnotes.enumerated()), id: \.offset) { _, note in
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mapRegion: MKCoordinateRegion {
        let bounds = polygons.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        let fitted = MKCoordinateRegion(bounds)
        return MKCoordinateRegion(
            center: fitted.center,
            span: MKCoordinateSpan(latitudeDelta: fitted.span.latitudeDelta * 1.2 + 0.01, longitudeDelta: fitted.span.longitudeDelta * 1.2 + 0.01)
        )
    }
}
