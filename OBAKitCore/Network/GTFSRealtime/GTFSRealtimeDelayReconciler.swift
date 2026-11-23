//
//  GTFSRealtimeDelayReconciler.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Reconcilable Protocols and Models

/// A protocol representing a scheduled trip event that can be reconciled with GTFS-RT updates.
public protocol GTFSRTReconcilableSchedule {
    var reconcilableTripID: String { get }
    var reconcilableStopID: String? { get }
    var reconcilableStopSequence: Int? { get }
    var scheduledArrivalDate: Date? { get }
    var scheduledDepartureDate: Date? { get }
    var reconcilableTripStopIDs: [String]? { get }
}

public extension GTFSRTReconcilableSchedule {
    var reconcilableTripStopIDs: [String]? { nil }
}

/// Standalone lightweight schedule event conforming to `GTFSRTReconcilableSchedule`.
public struct GTFSRTScheduleItem: GTFSRTReconcilableSchedule, Sendable, Equatable {
    public let reconcilableTripID: String
    public let reconcilableStopID: String?
    public let reconcilableStopSequence: Int?
    public let scheduledArrivalDate: Date?
    public let scheduledDepartureDate: Date?
    public let reconcilableTripStopIDs: [String]?

    public init(
        tripID: String,
        stopID: String? = nil,
        stopSequence: Int? = nil,
        scheduledArrival: Date? = nil,
        scheduledDeparture: Date? = nil,
        tripStopIDs: [String]? = nil
    ) {
        self.reconcilableTripID = tripID
        self.reconcilableStopID = stopID
        self.reconcilableStopSequence = stopSequence
        self.scheduledArrivalDate = scheduledArrival
        self.scheduledDepartureDate = scheduledDeparture
        self.reconcilableTripStopIDs = tripStopIDs
    }
}

/// Reconciled result combining a scheduled item with GTFS-RT real-time deviations and cancellations.
public struct GTFSRTReconciledSchedule<Item: GTFSRTReconcilableSchedule> {
    public let item: Item
    public let tripUpdate: GTFSRTTripUpdate?
    public let matchedStopTimeUpdate: GTFSRTStopTimeUpdate?

    public let isCanceled: Bool
    public let isSkipped: Bool
    public let isNoData: Bool

    public let tripScheduleRelationship: GTFSRTTripScheduleRelationship
    public let stopScheduleRelationship: GTFSRTStopTimeScheduleRelationship?

    public let arrivalDelay: Int?
    public let departureDelay: Int?

    public let reconciledArrival: Date?
    public let reconciledDeparture: Date?

    /// True if real-time delay or prediction information is active.
    public var isLive: Bool {
        tripUpdate != nil &&
            !isCanceled &&
            !isSkipped &&
            !isNoData &&
            (reconciledArrival != nil || reconciledDeparture != nil || arrivalDelay != nil || departureDelay != nil)
    }
}

extension GTFSRTReconciledSchedule: Sendable where Item: Sendable {}

// MARK: - Delay Reconciler Helper

/// Reconciles GTFS-RT TripUpdate data with REST models and schedules.
public struct GTFSRealtimeDelayReconciler: Sendable {
    public init() {}

    public static let standard = GTFSRealtimeDelayReconciler()

    private static let serviceDateFormatterUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let serviceDateFormatterCurrent: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Extracts the agency prefix from an identifier if present (e.g. "1_100" -> "1").
    public static func agencyPrefix(from identifier: String?) -> String? {
        guard let identifier, let idx = identifier.firstIndex(of: "_"), idx > identifier.startIndex else {
            return nil
        }
        return String(identifier[..<idx])
    }

    /// Strips the agency prefix from an identifier if present (e.g. "1_100" -> "100").
    public static func stripAgencyPrefix(from identifier: String) -> String {
        guard let idx = identifier.firstIndex(of: "_"), idx > identifier.startIndex else {
            return identifier
        }
        return String(identifier[identifier.index(after: idx)...])
    }

    /// Matches a feed trip ID against a REST trip ID, handling optional agency ID prefixes (e.g., "1_12345" vs "12345").
    /// Rejects false matches across different agencies (e.g. feed "100" with agency "1" does not match "40_100").
    public static func tripIDsMatch(feedTripID: String, restTripID: String, agencyID: String? = nil) -> Bool {
        if feedTripID == restTripID { return true }

        if let idx = restTripID.firstIndex(of: "_") {
            let prefix = String(restTripID[..<idx])
            let remainder = String(restTripID[restTripID.index(after: idx)...])
            if remainder == feedTripID {
                if let agencyID, prefix != agencyID { return false }
                return true
            }
        }

        if let idx = feedTripID.firstIndex(of: "_") {
            let prefix = String(feedTripID[..<idx])
            let remainder = String(feedTripID[feedTripID.index(after: idx)...])
            if remainder == restTripID {
                if let agencyID, prefix != agencyID { return false }
                return true
            }
        }

        return false
    }

    /// Matches a feed stop ID against a REST stop ID, handling optional agency ID prefixes.
    public static func stopIDsMatch(feedStopID: String?, restStopID: String?, agencyID: String? = nil) -> Bool {
        guard let feedStopID, let restStopID, !feedStopID.isEmpty, !restStopID.isEmpty else { return false }
        if feedStopID == restStopID { return true }

        if let idx = restStopID.firstIndex(of: "_") {
            let prefix = String(restStopID[..<idx])
            let remainder = String(restStopID[restStopID.index(after: idx)...])
            if remainder == feedStopID {
                if let agencyID, prefix != agencyID { return false }
                return true
            }
        }

        if let idx = feedStopID.firstIndex(of: "_") {
            let prefix = String(feedStopID[..<idx])
            let remainder = String(feedStopID[feedStopID.index(after: idx)...])
            if remainder == restStopID {
                if let agencyID, prefix != agencyID { return false }
                return true
            }
        }

        return false
    }

    private static func parseServiceDate(_ dateString: String) -> Date? {
        serviceDateFormatterUTC.date(from: dateString)
    }

    private func emptyReconciliation<Schedule: GTFSRTReconcilableSchedule>(for schedule: Schedule) -> GTFSRTReconciledSchedule<Schedule> {
        GTFSRTReconciledSchedule(
            item: schedule,
            tripUpdate: nil,
            matchedStopTimeUpdate: nil,
            isCanceled: false,
            isSkipped: false,
            isNoData: false,
            tripScheduleRelationship: .scheduled,
            stopScheduleRelationship: nil,
            arrivalDelay: nil,
            departureDelay: nil,
            reconciledArrival: nil,
            reconciledDeparture: nil
        )
    }

    private func determineUpstreamUpdates<Schedule: GTFSRTReconcilableSchedule>(
        schedule: Schedule,
        tripUpdate: GTFSRTTripUpdate,
        matchedStop: GTFSRTStopTimeUpdate?,
        stopOrder: [String]?,
        agencyID: String?
    ) -> [GTFSRTStopTimeUpdate] {
        if let schedSeq = schedule.reconcilableStopSequence, let targetSeq = UInt32(exactly: schedSeq) {
            let seqMatches = tripUpdate.stopTimeUpdates
                .filter { $0.stopSequence != nil && ($0.stopSequence ?? 0) < targetSeq }
                .sorted { ($0.stopSequence ?? 0) < ($1.stopSequence ?? 0) }
            if !seqMatches.isEmpty { return seqMatches }
        }

        if let order = stopOrder ?? schedule.reconcilableTripStopIDs,
           let myStopID = schedule.reconcilableStopID,
           let myIdx = order.firstIndex(where: { Self.stopIDsMatch(feedStopID: $0, restStopID: myStopID, agencyID: agencyID) }) {
            return tripUpdate.stopTimeUpdates.filter { update in
                guard let uStopID = update.stopID,
                      let uIdx = order.firstIndex(where: { Self.stopIDsMatch(feedStopID: uStopID, restStopID: $0, agencyID: agencyID) }) else { return false }
                return uIdx < myIdx
            }
        }

        if let matched = matchedStop, let idx = tripUpdate.stopTimeUpdates.firstIndex(where: { $0 == matched }) {
            return Array(tripUpdate.stopTimeUpdates[0..<idx])
        }

        return []
    }

    private func propagateUpstream(
        upstreamUpdates: [GTFSRTStopTimeUpdate],
        tripDelay: Int?
    ) -> (propagatedDelay: Int?, isUpstreamNoData: Bool) {
        var propagatedDelay = tripDelay
        var isUpstreamNoData = false

        for u in upstreamUpdates {
            if u.scheduleRelationship.isNoData {
                isUpstreamNoData = true
                propagatedDelay = nil
            } else if let dep = u.departureDelay {
                isUpstreamNoData = false
                propagatedDelay = dep
            } else if let arr = u.arrivalDelay {
                isUpstreamNoData = false
                propagatedDelay = arr
            }
        }

        return (propagatedDelay, isUpstreamNoData)
    }

    private func resolveNoData(
        isCanceled: Bool,
        isDirectNoData: Bool,
        matchedStop: GTFSRTStopTimeUpdate?,
        isUpstreamNoData: Bool
    ) -> Bool {
        if isCanceled { return false }
        if isDirectNoData { return true }
        guard let matchedStop else { return isUpstreamNoData }
        let hasData = matchedStop.departureDelay != nil || matchedStop.arrivalDelay != nil || matchedStop.departureTime != nil || matchedStop.arrivalTime != nil
        return hasData ? false : isUpstreamNoData
    }

    private func resolveDelays(
        isCanceledOrSkippedOrNoData: Bool,
        matchedStop: GTFSRTStopTimeUpdate?,
        propagatedDelay: Int?
    ) -> (arrivalDelay: Int?, departureDelay: Int?) {
        guard !isCanceledOrSkippedOrNoData else { return (nil, nil) }
        let arr = matchedStop?.arrivalDelay ?? propagatedDelay
        let dep = matchedStop?.departureDelay ?? matchedStop?.arrivalDelay ?? propagatedDelay
        return (arr, dep)
    }

    private func resolveReconciledDates<Schedule: GTFSRTReconcilableSchedule>(
        schedule: Schedule,
        matchedStop: GTFSRTStopTimeUpdate?,
        isCanceledOrSkippedOrNoData: Bool,
        arrivalDelay: Int?,
        departureDelay: Int?
    ) -> (reconciledArrival: Date?, reconciledDeparture: Date?) {
        guard !isCanceledOrSkippedOrNoData else { return (nil, nil) }

        let recArr: Date?
        if let exactArrival = matchedStop?.arrivalTime {
            recArr = exactArrival
        } else if let arrivalDelay, let schedArr = schedule.scheduledArrivalDate {
            recArr = schedArr.addingTimeInterval(TimeInterval(arrivalDelay))
        } else {
            recArr = nil
        }

        let recDep: Date?
        if let exactDeparture = matchedStop?.departureTime {
            recDep = exactDeparture
        } else if let departureDelay, let schedDep = schedule.scheduledDepartureDate {
            recDep = schedDep.addingTimeInterval(TimeInterval(departureDelay))
        } else {
            recDep = nil
        }

        return (recArr, recDep)
    }

    /// Reconciles an arbitrary `GTFSRTReconcilableSchedule` with an optional matching `GTFSRTTripUpdate`.
    public func reconcile<Schedule: GTFSRTReconcilableSchedule>(
        schedule: Schedule,
        with tripUpdate: GTFSRTTripUpdate?,
        stopOrder: [String]? = nil,
        agencyID: String? = nil
    ) -> GTFSRTReconciledSchedule<Schedule> {
        guard let tripUpdate else {
            return emptyReconciliation(for: schedule)
        }

        let isTripCanceled = tripUpdate.scheduleRelationship.isCanceledOrDeleted
        let matchedStop = findMatchingStopTimeUpdate(for: schedule, in: tripUpdate, agencyID: agencyID)
        let isStopSkipped = matchedStop?.scheduleRelationship.isSkipped ?? false
        let isDirectNoData = matchedStop?.scheduleRelationship.isNoData ?? false

        let upstream = determineUpstreamUpdates(
            schedule: schedule,
            tripUpdate: tripUpdate,
            matchedStop: matchedStop,
            stopOrder: stopOrder,
            agencyID: agencyID
        )
        let (propagatedDelay, isUpstreamNoData) = propagateUpstream(upstreamUpdates: upstream, tripDelay: tripUpdate.tripDelay)

        let isNoData = resolveNoData(isCanceled: isTripCanceled, isDirectNoData: isDirectNoData, matchedStop: matchedStop, isUpstreamNoData: isUpstreamNoData)
        let (arrDelay, depDelay) = resolveDelays(isCanceledOrSkippedOrNoData: isTripCanceled || isStopSkipped || isNoData, matchedStop: matchedStop, propagatedDelay: propagatedDelay)
        let (recArrival, recDeparture) = resolveReconciledDates(
            schedule: schedule,
            matchedStop: matchedStop,
            isCanceledOrSkippedOrNoData: isTripCanceled || isStopSkipped || isNoData,
            arrivalDelay: arrDelay,
            departureDelay: depDelay
        )

        return GTFSRTReconciledSchedule(
            item: schedule,
            tripUpdate: tripUpdate,
            matchedStopTimeUpdate: matchedStop,
            isCanceled: isTripCanceled,
            isSkipped: isStopSkipped,
            isNoData: isNoData,
            tripScheduleRelationship: tripUpdate.scheduleRelationship,
            stopScheduleRelationship: matchedStop?.scheduleRelationship,
            arrivalDelay: arrDelay,
            departureDelay: depDelay,
            reconciledArrival: recArrival,
            reconciledDeparture: recDeparture
        )
    }

    private func findExactSequenceAndStopMatch<Schedule: GTFSRTReconcilableSchedule>(
        for schedule: Schedule,
        in tripUpdate: GTFSRTTripUpdate,
        agencyID: String?
    ) -> GTFSRTStopTimeUpdate? {
        guard let schedSeq = schedule.reconcilableStopSequence,
              let targetSeq = UInt32(exactly: schedSeq),
              let schedStopID = schedule.reconcilableStopID,
              !schedStopID.isEmpty else { return nil }

        return tripUpdate.stopTimeUpdates.first {
            $0.stopSequence == targetSeq && Self.stopIDsMatch(feedStopID: $0.stopID, restStopID: schedStopID, agencyID: agencyID)
        }
    }

    private func findSequenceMatch<Schedule: GTFSRTReconcilableSchedule>(
        for schedule: Schedule,
        in tripUpdate: GTFSRTTripUpdate,
        agencyID: String?
    ) -> GTFSRTStopTimeUpdate? {
        guard let schedSeq = schedule.reconcilableStopSequence,
              let targetSeq = UInt32(exactly: schedSeq) else { return nil }

        return tripUpdate.stopTimeUpdates.first {
            guard $0.stopSequence == targetSeq else { return false }
            if let updateStopID = $0.stopID, let schedStopID = schedule.reconcilableStopID, !updateStopID.isEmpty, !schedStopID.isEmpty {
                return Self.stopIDsMatch(feedStopID: updateStopID, restStopID: schedStopID, agencyID: agencyID)
            }
            return true
        }
    }

    private func findStopIDMatch<Schedule: GTFSRTReconcilableSchedule>(
        for schedule: Schedule,
        in tripUpdate: GTFSRTTripUpdate,
        agencyID: String?
    ) -> GTFSRTStopTimeUpdate? {
        guard let schedStopID = schedule.reconcilableStopID, !schedStopID.isEmpty else { return nil }

        let candidates = tripUpdate.stopTimeUpdates.filter { update in
            guard Self.stopIDsMatch(feedStopID: update.stopID, restStopID: schedStopID, agencyID: agencyID) else { return false }
            if let schedSeq = schedule.reconcilableStopSequence,
               let targetSeq = UInt32(exactly: schedSeq),
               let updateSeq = update.stopSequence {
                return targetSeq == updateSeq
            }
            return true
        }

        if candidates.count <= 1 { return candidates.first }

        if let targetDate = schedule.scheduledArrivalDate ?? schedule.scheduledDepartureDate {
            return candidates.min { a, b in
                let dateA = a.arrivalTime ?? a.departureTime ?? .distantPast
                let dateB = b.arrivalTime ?? b.departureTime ?? .distantPast
                return abs(dateA.timeIntervalSince(targetDate)) < abs(dateB.timeIntervalSince(targetDate))
            }
        }
        return candidates.first
    }

    /// Finds matching `GTFSRTStopTimeUpdate` by stop ID or stop sequence, resolving sequence conflicts and loop route visits.
    public func findMatchingStopTimeUpdate<Schedule: GTFSRTReconcilableSchedule>(
        for schedule: Schedule,
        in tripUpdate: GTFSRTTripUpdate,
        agencyID: String? = nil
    ) -> GTFSRTStopTimeUpdate? {
        if let exact = findExactSequenceAndStopMatch(for: schedule, in: tripUpdate, agencyID: agencyID) {
            return exact
        }
        if let bySeq = findSequenceMatch(for: schedule, in: tripUpdate, agencyID: agencyID) {
            return bySeq
        }
        return findStopIDMatch(for: schedule, in: tripUpdate, agencyID: agencyID)
    }

    /// Reconciles an `ArrivalDeparture` instance with an optional matching `GTFSRTTripUpdate`.
    public func reconcile(
        arrivalDeparture: ArrivalDeparture,
        with tripUpdate: GTFSRTTripUpdate?,
        stopOrder: [String]? = nil,
        agencyID: String? = nil
    ) -> ReconciledArrivalDeparture {
        return reconcile(schedule: arrivalDeparture, with: tripUpdate, stopOrder: stopOrder, agencyID: agencyID)
    }

    private func updateMatches(update: GTFSRTTripUpdate, arrDep: ArrivalDeparture, agency: String?) -> Bool {
        guard Self.tripIDsMatch(feedTripID: update.tripID, restTripID: arrDep.tripID, agencyID: agency) else {
            return false
        }
        if let updateRouteID = update.routeID, !updateRouteID.isEmpty {
            return Self.stopIDsMatch(feedStopID: updateRouteID, restStopID: arrDep.routeID, agencyID: agency)
        }
        return true
    }

    private func selectBestTripUpdate(
        from matchingUpdates: [GTFSRTTripUpdate],
        for arrDep: ArrivalDeparture,
        timeZone: TimeZone? = nil
    ) -> GTFSRTTripUpdate? {
        if matchingUpdates.isEmpty { return nil }

        let tz = timeZone ?? arrDep.trip?.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = tz
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let expectedDateString = formatter.string(from: arrDep.serviceDate)

        if let exact = matchingUpdates.first(where: { $0.startDate == expectedDateString }) {
            return exact
        }

        let updatesWithDate = matchingUpdates.compactMap { update -> (GTFSRTTripUpdate, TimeInterval)? in
            guard let s = update.startDate, let d = formatter.date(from: s) else { return nil }
            return (update, abs(d.timeIntervalSince(arrDep.serviceDate)))
        }.sorted { $0.1 < $1.1 }

        if let best = updatesWithDate.first {
            return best.1 <= 36.0 * 3600.0 ? best.0 : nil
        }

        return matchingUpdates.count == 1 ? matchingUpdates[0] : nil
    }

    /// Reconciles an array of `ArrivalDeparture` instances with an array of `GTFSRTTripUpdate` models.
    public func reconcile(
        arrivalDepartures: [ArrivalDeparture],
        with tripUpdates: [GTFSRTTripUpdate],
        agencyID: String? = nil,
        timeZone: TimeZone? = nil
    ) -> [ReconciledArrivalDeparture] {
        return arrivalDepartures.map { arrDep in
            let matchingUpdates = tripUpdates.filter { updateMatches(update: $0, arrDep: arrDep, agency: agencyID) }
            let selected = selectBestTripUpdate(from: matchingUpdates, for: arrDep, timeZone: timeZone)
            return reconcile(arrivalDeparture: arrDep, with: selected, agencyID: agencyID)
        }
    }
}

// MARK: - ArrivalDeparture Extensions

public typealias ReconciledArrivalDeparture = GTFSRTReconciledSchedule<ArrivalDeparture>

extension ArrivalDeparture: GTFSRTReconcilableSchedule {
    public var reconcilableTripID: String { tripID }
    public var reconcilableStopID: String? { stopID }
    public var reconcilableStopSequence: Int? { gtfsStopSequence }
    public var scheduledArrivalDate: Date? { scheduledArrival }
    public var scheduledDepartureDate: Date? { scheduledDeparture }

    private struct ResolvedPredictions {
        let predicted: Bool
        let arrival: Date?
        let departure: Date?
    }

    private struct ResolvedStatusAndBoarding {
        let status: String
        let arrivalEnabled: Bool
        let departureEnabled: Bool
    }

    private func resolvePredictions(reconciliation: ReconciledArrivalDeparture) -> ResolvedPredictions {
        if reconciliation.isCanceled || reconciliation.isNoData || reconciliation.isSkipped {
            return ResolvedPredictions(predicted: false, arrival: nil, departure: nil)
        } else if reconciliation.isLive {
            return ResolvedPredictions(
                predicted: true,
                arrival: reconciliation.reconciledArrival ?? predictedArrival,
                departure: reconciliation.reconciledDeparture ?? predictedDeparture
            )
        } else {
            return ResolvedPredictions(predicted: predicted, arrival: predictedArrival, departure: predictedDeparture)
        }
    }

    private func resolveStatusAndBoarding(reconciliation: ReconciledArrivalDeparture) -> ResolvedStatusAndBoarding {
        if reconciliation.isCanceled {
            return ResolvedStatusAndBoarding(status: "canceled", arrivalEnabled: false, departureEnabled: false)
        } else if reconciliation.isSkipped {
            return ResolvedStatusAndBoarding(status: "skipped", arrivalEnabled: false, departureEnabled: false)
        } else if reconciliation.tripUpdate != nil && (status == "canceled" || status == "skipped") {
            return ResolvedStatusAndBoarding(status: "default", arrivalEnabled: true, departureEnabled: true)
        } else {
            return ResolvedStatusAndBoarding(status: status, arrivalEnabled: arrivalEnabled, departureEnabled: departureEnabled)
        }
    }

    private func buildUpdatedTripStatus(reconciliation: ReconciledArrivalDeparture) -> TripStatus? {
        if reconciliation.isCanceled {
            if let tripStatus {
                return tripStatus.updating(statusModifier: .canceled, isRealTime: false)
            } else {
                return TripStatus(
                    activeTripID: tripID,
                    closestStopID: stopID,
                    isRealTime: false,
                    serviceDate: serviceDate,
                    statusModifier: .canceled,
                    vehicleID: reconciliation.tripUpdate?.vehicleID ?? vehicleID,
                    regionIdentifier: regionIdentifier,
                    activeTrip: trip,
                    closestStop: stop
                )
            }
        } else if let tripStatus {
            let updatedRealTime = reconciliation.isNoData ? false : (reconciliation.isLive ? true : tripStatus.isRealTime)
            let updatedDev = reconciliation.arrivalDelay.map(TimeInterval.init) ?? tripStatus.scheduleDeviation
            let updatedLastUp = reconciliation.tripUpdate?.timestamp ?? tripStatus.lastUpdate
            let updatedVeh = reconciliation.tripUpdate?.vehicleID ?? tripStatus.vehicleID
            return tripStatus.updating(
                statusModifier: .default,
                isRealTime: updatedRealTime,
                scheduleDeviation: updatedDev,
                lastUpdate: updatedLastUp,
                vehicleID: updatedVeh
            )
        }
        return nil
    }

    /// Applies a reconciled update, creating an updated `ArrivalDeparture` instance.
    public func applying(reconciliation: ReconciledArrivalDeparture) -> ArrivalDeparture {
        let pred = resolvePredictions(reconciliation: reconciliation)
        let stat = resolveStatusAndBoarding(reconciliation: reconciliation)
        let updatedTripStatus = buildUpdatedTripStatus(reconciliation: reconciliation)

        return ArrivalDeparture(
            arrivalEnabled: stat.arrivalEnabled,
            blockTripSequence: blockTripSequence,
            departureEnabled: stat.departureEnabled,
            distanceFromStop: distanceFromStop,
            frequency: frequency,
            lastUpdated: reconciliation.tripUpdate?.timestamp ?? lastUpdated,
            numberOfStopsAway: numberOfStopsAway,
            predicted: pred.predicted,
            predictedArrival: pred.arrival,
            predictedDeparture: pred.departure,
            routeID: routeID,
            route: route,
            routeLongName: _routeLongName,
            routeShortName: _routeShortName,
            scheduledArrival: scheduledArrival,
            scheduledDeparture: scheduledDeparture,
            serviceDate: serviceDate,
            situationIDs: situationIDs,
            serviceAlerts: serviceAlerts,
            status: stat.status,
            stopID: stopID,
            stop: stop,
            stopSequence: stopSequence,
            gtfsStopSequence: gtfsStopSequence,
            totalStopsInTrip: totalStopsInTrip,
            tripHeadsign: _tripHeadsign,
            tripID: tripID,
            trip: trip,
            tripStatus: updatedTripStatus,
            vehicleID: reconciliation.tripUpdate?.vehicleID ?? vehicleID,
            regionIdentifier: regionIdentifier,
            occupancyStatus: reconciliation.matchedStopTimeUpdate?.departureOccupancyStatus.flatMap(OccupancyStatus.init(protobuf:)) ?? occupancyStatus,
            historicalOccupancyStatus: historicalOccupancyStatus
        )
    }
}

extension GTFSRTReconciledSchedule where Item == ArrivalDeparture {
    public var arrivalDeparture: ArrivalDeparture { item }

    /// Reconciled date for display based on arrival/departure status.
    public var reconciledDate: Date {
        if isNoData {
            switch item.arrivalDepartureStatus {
            case .arriving:
                return item.scheduledArrival
            case .departing:
                return item.scheduledDeparture
            }
        }
        if isLive {
            switch item.arrivalDepartureStatus {
            case .arriving:
                return reconciledArrival ?? item.arrivalDepartureDate
            case .departing:
                return reconciledDeparture ?? item.arrivalDepartureDate
            }
        }
        return item.arrivalDepartureDate
    }

    /// Evaluates the real-time schedule deviation into an early, onTime, or delayed status.
    public var scheduleStatus: ScheduleStatus {
        guard isLive else {
            return item.scheduleStatus
        }
        let deviationSeconds: TimeInterval
        switch item.arrivalDepartureStatus {
        case .arriving:
            if let recArr = reconciledArrival {
                deviationSeconds = recArr.timeIntervalSince(item.scheduledArrival)
            } else if let arrDelay = arrivalDelay ?? departureDelay {
                deviationSeconds = TimeInterval(arrDelay)
            } else {
                return item.scheduleStatus
            }
        case .departing:
            if let recDep = reconciledDeparture {
                deviationSeconds = recDep.timeIntervalSince(item.scheduledDeparture)
            } else if let depDelay = departureDelay ?? arrivalDelay {
                deviationSeconds = TimeInterval(depDelay)
            } else {
                return item.scheduleStatus
            }
        }
        let minutesDiff = deviationSeconds / 60.0
        if minutesDiff < -1.5 {
            return .early
        } else if minutesDiff < 1.5 {
            return .onTime
        } else {
            return .delayed
        }
    }
}

// MARK: - ScheduleForStop Extensions

extension ScheduleForStop.StopScheduleStopTime: GTFSRTReconcilableSchedule {
    public var reconcilableTripID: String { tripID }
    public var reconcilableStopID: String? { stopID }
    public var reconcilableStopSequence: Int? { nil }
    public var scheduledArrivalDate: Date? { arrivalDate }
    public var scheduledDepartureDate: Date? { departureDate }
}
