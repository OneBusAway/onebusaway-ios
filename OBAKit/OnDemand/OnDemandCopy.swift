//
//  OnDemandCopy.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Spec 2.8: turns availability, matches and edges into rider-facing text.
/// Every surface composes through this type so the card, bar, picker and
/// detail page can never disagree about a status.
struct OnDemandCopy {

    enum StatusStyle {
        /// "Open · until 4:40 PM" (card, picker, bar).
        case card
        /// "Open now · until 4:40 PM" (service page).
        case detail
    }

    let timeZone: TimeZone
    let locale: Locale
    let now: Date

    init(timeZone: TimeZone, locale: Locale = .current, now: Date) {
        self.timeZone = timeZone
        self.locale = locale
        self.now = now
    }

    /// The same locale and clock in `service`'s agency zone; a bar stack can
    /// mix agencies. Falls back to this copy's zone when the service has none.
    func forService(_ service: OnDemandService) -> OnDemandCopy {
        OnDemandCopy(timeZone: service.timeZone ?? timeZone, locale: locale, now: now)
    }

    // MARK: - Distance and time

    private static let metersPerMile = 1609.344
    private static let feetPerMeter = 3.28084

    /// Imperial: whole feet rounded to 10 below 0.1 mi, else miles with one
    /// decimal. Metric: metres rounded to 10 below 1 km, else km with one decimal.
    func distance(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium

        let usesImperial = locale.measurementSystem == .us || locale.measurementSystem == .uk
        if usesImperial {
            let miles = meters / Self.metersPerMile
            if miles < 0.1 {
                formatter.numberFormatter.maximumFractionDigits = 0
                let feet = (meters * Self.feetPerMeter / 10).rounded() * 10
                return formatter.string(from: Measurement(value: feet, unit: UnitLength.feet))
            }
            formatter.numberFormatter.minimumFractionDigits = 1
            formatter.numberFormatter.maximumFractionDigits = 1
            return formatter.string(from: Measurement(value: miles, unit: UnitLength.miles))
        }

        if meters < 1000 {
            formatter.numberFormatter.maximumFractionDigits = 0
            return formatter.string(from: Measurement(value: (meters / 10).rounded() * 10, unit: UnitLength.meters))
        }
        formatter.numberFormatter.minimumFractionDigits = 1
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: meters / 1000, unit: UnitLength.kilometers))
    }

    /// Short time style in the agency zone, e.g. "4:40 PM".
    func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "tomorrow at 7:20 AM", through the summary's relative formatter.
    func relativeDateTime(_ date: Date) -> String {
        OnDemandServiceSummary.formattedRelativeDateTime(date, now: now, timeZone: timeZone, locale: locale)
    }

    // MARK: - Status and tags

    func statusText(_ status: OnDemandStatus, style: StatusStyle) -> String? {
        switch status {
        case .openNow(let until):
            guard let until else { return Strings.onDemandStatusOpen }
            let format = style == .detail ? Strings.onDemandStatusOpenNowUntilFormat : Strings.onDemandStatusOpenUntilFormat
            return String(format: format, time(until))
        case .opensAt(let start):
            return String(format: Strings.onDemandStatusOpensFormat, relativeDateTime(start))
        case .bookingOpens(let open):
            return String(format: Strings.onDemandBookingOpensFormat, relativeDateTime(open))
        case .bookBy(let deadline, _):
            return String(format: Strings.onDemandStatusBookByFormat, relativeDateTime(deadline))
        case .closed:
            return Strings.onDemandStatusClosed
        case .unknown:
            return nil
        }
    }

    func tagText(_ tag: OnDemandAvailability.Tag) -> String {
        switch tag {
        case .noNoticeNeeded: return Strings.onDemandTagNoNotice
        case .sameDayBooking: return Strings.onDemandTagSameDay
        case .advanceBooking: return Strings.onDemandTagAdvance
        case .eligibilityRequired: return Strings.onDemandTagEligibility
        }
    }

    /// The single booking tag (never the eligibility tag).
    func bookingTag(_ availability: OnDemandAvailability) -> OnDemandAvailability.Tag? {
        availability.tags.first { $0 != .eligibilityRequired }
    }

    /// Status and booking tag joined with " · ", empty segments omitted; nil when both are empty.
    func cardMeta(_ availability: OnDemandAvailability) -> String? {
        let segments = [statusText(availability.status, style: .card), bookingTag(availability).map(tagText)].compactMap { $0 }
        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    /// Area names joined with ", " (or the zone count when none is named), then " · ", then the booking tag.
    func pickerSecondLine(areaNames: [String], areaCount: Int, availability: OnDemandAvailability) -> String {
        let areas = areaNames.isEmpty ? Self.zoneCount(areaCount) : areaNames.joined(separator: ", ")
        guard let tag = bookingTag(availability) else { return areas }
        return "\(areas) · \(tagText(tag))"
    }

    // MARK: - Bar title (spec 2.8 precedence)

    /// - Parameter edge: the resolved edge for this match — the server point
    ///   with the server distance when outside, the client geometry otherwise.
    ///   Nil when neither is known.
    func barTitle(for match: OnDemandServiceMatch, edge: OnDemandEdge?) -> String? {
        if !match.isInside {
            guard let edge else { return nil }
            return String(format: Strings.onDemandBarOutsideFormat(edge.riderDirection), distance(edge.distanceMeters))
        }
        // A distance of exactly 0 has no meaningful direction to walk — that's
        // plain "inside", not a near-edge title (ruling: spec 2.7/2.8).
        if let edge, edge.distanceMeters > 0, edge.distanceMeters < OnDemandGeometry.nearEdgeMeters {
            return String(format: Strings.onDemandBarInsideNearEdgeFormat(edge.edgeDirection), distance(edge.distanceMeters))
        }

        let availability = match.availability
        switch availability.usabilityTier {
        case OnDemandAvailability.eligibilityTier:
            return tagText(.eligibilityRequired)
        case OnDemandAvailability.advanceTier:
            return bookingLineTitle(availability)
        case OnDemandAvailability.sameDayTier:
            return statusText(availability.status, style: .card)
        case OnDemandAvailability.unknownTier:
            return availability.status == .closed ? Strings.onDemandStatusClosed : nil
        default:
            return Strings.onDemandBarInside
        }
    }

    /// Tier 3 reads the evaluator's booking line (spec 2.8 `book_by`, or
    /// `booking_opens` when booking has not opened), so the title names the
    /// next thing the rider can do; a line with no instant falls back to the
    /// status.
    private func bookingLineTitle(_ availability: OnDemandAvailability) -> String? {
        switch availability.bookingResolution {
        case .bookBy(let cutoff, _):
            return String(format: Strings.onDemandStatusBookByFormat, relativeDateTime(cutoff))
        case .opensAt(let open):
            return String(format: Strings.onDemandBookingOpensFormat, relativeDateTime(open))
        case .noNoticeRequired, .closed, .unknown:
            return statusText(availability.status, style: .card)
        }
    }

    // MARK: - Counts

    static func badge(index: Int, count: Int) -> String {
        String(format: Strings.onDemandBarBadgeFormat, index, count)
    }

    static func moreServices(_ count: Int) -> String {
        String.localizedStringWithFormat(Strings.onDemandCardMoreServicesFormat, count)
    }

    static func pickerTitle(count: Int, nearby: Bool) -> String {
        String.localizedStringWithFormat(nearby ? Strings.onDemandPickerTitleNearbyFormat : Strings.onDemandPickerTitleFormat, count)
    }

    static func zoneCount(_ count: Int) -> String {
        String.localizedStringWithFormat(Strings.onDemandDetailZoneCountFormat, count)
    }

    static func addressInsideMore(name: String, extra: Int) -> String {
        String.localizedStringWithFormat(Strings.onDemandAddressInsideMoreFormat, name, extra)
    }
}
