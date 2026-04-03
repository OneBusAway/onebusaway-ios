//
//  TripStopListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - TripStopListView

struct TripStopListView: View {
    let header: TripPanelHeaderViewModel
    let stops: [TripStopRowViewModel]
    let onSelectStop: (TripStopRowViewModel) -> Void
    var onShowOnMap: ((TripStopRowViewModel) -> Void)? = nil
    var refreshAction: (() async -> Void)? = nil
    var serviceAlerts: [String] = []

    // MARK: - State

    @State private var pastStopsExpanded = false
    @State private var showJumpButton = false
    /// Shared scroll proxy so the Jump button can actually scroll the list.
    @State private var scrollProxy: ScrollViewProxy? = nil

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            grabberHandle

            TripPanelHeaderView(
                routeHeadsign: header.routeHeadsign,
                scheduledTime: header.scheduledTime,
                statusText: header.statusText,
                minutesUntilArrival: header.minutesUntilArrival,
                isRealTime: header.isRealTime,
                nextStopName: nextStop?.stopName,
                nextStopTime: nextStop?.arrivalTime,
                routeProgress: routeProgress,
                stopsRemaining: upcomingStops.count,
                scheduleDeviationMinutes: nextStop?.delayMinutes
            )

            Divider()

            if stops.isEmpty {
                emptyState
            } else {
                ZStack(alignment: .bottom) {
                    stopList
                    if showJumpButton {
                        jumpToNowButton
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Stop list

    private var stopList: some View {
        ScrollViewReader { proxy in
            List {
                // ── Service alert banners ────────────────────────────────
                if !serviceAlerts.isEmpty {
                    Section {
                        ForEach(serviceAlerts, id: \.self) { alert in
                            ServiceAlertBanner(text: alert)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color(.systemBackground))
                        }
                    }
                }

                // ── Past stops (collapsible) ─────────────────────────────
                if !pastStops.isEmpty {
                    Section {
                        if pastStopsExpanded {
                            ForEach(pastStops) { stop in stopButton(stop) }
                        }
                    } header: {
                        CollapsibleSectionHeader(
                            title: "Passed stops (\(pastStops.count))",
                            isExpanded: pastStopsExpanded
                        ) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                pastStopsExpanded.toggle()
                            }
                        }
                    }
                }

                // ── Current vehicle stop ─────────────────────────────────
                if let current = currentStop {
                    Section {
                        stopButton(current).id("__current__")
                    } header: {
                        sectionLabel("Now", systemImage: "location.fill", color: Color(.systemGreen))
                    }
                }

                // ── Upcoming stops ───────────────────────────────────────
                if !upcomingStops.isEmpty {
                    Section {
                        ForEach(upcomingStops) { stop in
                            stopButton(stop).id(stop.id)
                        }
                    } header: {
                        // ⊙ matches the clock icon shown in the screenshot
                        sectionLabel("Upcoming", systemImage: "clock.arrow.circlepath", color: .secondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .applyRefreshable(action: refreshAction)
            .onAppear {
                scrollProxy = proxy
                // Auto-scroll to vehicle or first upcoming stop
                let focusID: String?
                if currentStop != nil {
                    focusID = "__current__"
                } else {
                    focusID = upcomingStops.first?.id
                }
                if let id = focusID {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            // Detect when "__current__" row scrolls out of view to show Jump button.
            // We use a background anchor preference on a sentinel view placed at the
            // current-stop row position.
            .background(
                GeometryReader { listGeo in
                    Color.clear.preference(
                        key: CurrentStopVisibilityKey.self,
                        value: listGeo.frame(in: .global).minY
                    )
                }
            )
            .onPreferenceChange(CurrentStopVisibilityKey.self) { _ in
                // Intentionally empty — visibility is tracked via the sentinel below
            }
        }
        // Sentinel: invisible view anchored to the current stop row that reports
        // whether it is on-screen. We approximate this by watching the list's
        // own scroll offset via a named coordinate space.
        .coordinateSpace(name: "tripList")
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CurrentStopVisibilityKey.self,
                    value: geo.frame(in: .named("tripList")).minY
                )
            }
        )
        .onPreferenceChange(CurrentStopVisibilityKey.self) { offset in
            guard currentStop != nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showJumpButton = offset < -80
            }
        }
    }

    // MARK: - Stop button

    @ViewBuilder
    private func stopButton(_ stop: TripStopRowViewModel) -> some View {
        Button { onSelectStop(stop) } label: {
            TripStopRow(viewModel: stop)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemBackground))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onShowOnMap {
                Button { onShowOnMap(stop) } label: {
                    Label("Map", systemImage: "mappin.circle.fill")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Section headers

    private func sectionLabel(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .padding(.leading, 56)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Jump to Now button

    private var jumpToNowButton: some View {
        Button {
            withAnimation { scrollProxy?.scrollTo("__current__", anchor: .top) }
            withAnimation(.easeInOut(duration: 0.2)) { showJumpButton = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.caption.weight(.bold))
                Text("Jump to Now")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGreen), in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .accessibilityLabel("Jump to current vehicle position")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bus.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Loading trip details…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading trip details")
    }

    // MARK: - Grabber

    private var grabberHandle: some View {
        Capsule()
            .fill(Color(.systemFill))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    // MARK: - Derived data

    private var pastStops: [TripStopRowViewModel]     { stops.filter { $0.isPast } }
    private var currentStop: TripStopRowViewModel?    { stops.first { $0.isCurrentVehicleLocation } }
    private var upcomingStops: [TripStopRowViewModel] { stops.filter { !$0.isPast && !$0.isCurrentVehicleLocation } }
    private var nextStop: TripStopRowViewModel?       { upcomingStops.first }

    private var routeProgress: Double? {
        guard !stops.isEmpty else { return nil }
        let passed = pastStops.count + (currentStop != nil ? 1 : 0)
        return Double(passed) / Double(stops.count)
    }
}

// MARK: - CollapsibleSectionHeader

private struct CollapsibleSectionHeader: View {
    let title: String
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            .padding(.leading, 56)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .accessibilityLabel(title)
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
    }
}

// MARK: - ServiceAlertBanner

private struct ServiceAlertBanner: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
        .accessibilityLabel("Service alert: \(text)")
    }
}

// MARK: - CurrentStopVisibilityKey

private struct CurrentStopVisibilityKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Refreshable helper (avoids shadowing system modifier)

private extension View {
    @ViewBuilder
    func applyRefreshable(action: (() async -> Void)?) -> some View {
        if let action {
            self.refreshable { await action() }
        } else {
            self
        }
    }
}

// MARK: - TripPanelHeaderViewModel

struct TripPanelHeaderViewModel {
    let routeHeadsign: String
    let scheduledTime: String
    let statusText: String
    let minutesUntilArrival: Int?
    let isRealTime: Bool

    init(arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
        self.routeHeadsign = arrivalDeparture.routeAndHeadsign
        self.scheduledTime = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
        self.isRealTime    = arrivalDeparture.predicted

        let minutes = Int(arrivalDeparture.arrivalDepartureDate.timeIntervalSinceNow / 60)
        self.minutesUntilArrival = minutes >= 0 ? minutes : nil

        self.statusText = arrivalDeparture.predicted
            ? formatters.formattedScheduleDeviation(for: arrivalDeparture)
            : OBALoc("departure_status.scheduled",
                     value: "Scheduled/not real-time",
                     comment: "Indicates a departure time is from the schedule, not real-time data")
    }

    init(routeHeadsign: String, scheduledTime: String, statusText: String,
         minutesUntilArrival: Int?, isRealTime: Bool) {
        self.routeHeadsign       = routeHeadsign
        self.scheduledTime       = scheduledTime
        self.statusText          = statusText
        self.minutesUntilArrival = minutesUntilArrival
        self.isRealTime          = isRealTime
    }
}

// MARK: - TripStopRowViewModel builder

extension TripStopRowViewModel {
    static func viewModels(
        from tripDetails: TripDetails,
        arrivalDeparture: ArrivalDeparture?,
        formatters: Formatters,
        onSelect: @escaping (TripStopRowViewModel) -> Void
    ) -> [TripStopRowViewModel] {
        let stopTimes = tripDetails.stopTimes
        guard !stopTimes.isEmpty else { return [] }

        let vehicleStopID = arrivalDeparture?.tripStatus?.closestStopID
        let vehicleIndex  = stopTimes.firstIndex { $0.stopID == vehicleStopID }

        let deviationMinutes: Int?
        if let dev = arrivalDeparture?.tripStatus?.scheduleDeviation {
            let mins = Int(dev / 60)
            deviationMinutes = mins == 0 ? nil : mins
        } else {
            deviationMinutes = nil
        }

        var result: [TripStopRowViewModel] = []

        // ── Previous trip row ────────────────────────────────────────────
        if let prev = tripDetails.previousTrip {
            result.append(TripStopRowViewModel(
                id: "adjacent_prev_\(prev.id)",
                stopName: prev.routeHeadsign,
                arrivalTime: "",
                segment: .adjacentPrev,
                routeType: .bus,
                isCurrentVehicleLocation: false,
                isUserDestination: false,
                isAdjacentTrip: true,
                adjacentTripLabel: "Starts as"
            ))
        }

        // ── Stop times ───────────────────────────────────────────────────
        for (index, stopTime) in stopTimes.enumerated() {
            let segment: TripRouteSegment
            if index == 0                        { segment = .first }
            else if index == stopTimes.count - 1 { segment = .last }
            else                                 { segment = .middle }

            let isPast = vehicleIndex.map { index < $0 } ?? false

            result.append(TripStopRowViewModel(
                id: stopTime.stopID,
                stopName: stopTime.stop.name,
                arrivalTime: formatters.timeFormatter.string(from: stopTime.arrivalDate),
                segment: segment,
                routeType: stopTime.stop.prioritizedRouteTypeForDisplay,
                isCurrentVehicleLocation: vehicleStopID != nil && stopTime.stopID == vehicleStopID,
                isUserDestination: arrivalDeparture.map { stopTime.stopID == $0.stopID } ?? false,
                isAdjacentTrip: false,
                adjacentTripLabel: nil,
                isPast: isPast,
                delayMinutes: isPast ? nil : deviationMinutes
            ))
        }

        // ── Next trip row ────────────────────────────────────────────────
        if let next = tripDetails.nextTrip {
            result.append(TripStopRowViewModel(
                id: "adjacent_next_\(next.id)",
                stopName: next.routeHeadsign,
                arrivalTime: "",
                segment: .adjacentNext,
                routeType: .bus,
                isCurrentVehicleLocation: false,
                isUserDestination: false,
                isAdjacentTrip: true,
                adjacentTripLabel: "Continues as"
            ))
        }

        return result
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Full Sheet — late, with alerts, dark") {
    let header = TripPanelHeaderViewModel(
        routeHeadsign: "SIM33C - MIDTOWN via CHURCH via MADISON AV",
        scheduledTime: "10:19 PM",
        statusText: "Scheduled/not real-time",
        minutesUntilArrival: 36,
        isRealTime: false
    )

    let stops: [TripStopRowViewModel] = [
        .init(id: "0", stopName: "Starts as SIM33",         arrivalTime: "", segment: .adjacentPrev, routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: true,  adjacentTripLabel: "Starts as",   isPast: false, delayMinutes: nil),
        .init(id: "1", stopName: "SOUTH AV/RICHMOND TERR",  arrivalTime: "9:15 PM", segment: .first,  routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: true,  delayMinutes: nil),
        .init(id: "2", stopName: "SOUTH AV/ARLINGTON PL",   arrivalTime: "9:16 PM", segment: .middle, routeType: .bus, isCurrentVehicleLocation: true,  isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: false, delayMinutes: nil),
        .init(id: "3", stopName: "GREENWICH ST/BATTERY PL", arrivalTime: "10:19 PM", segment: .middle, routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: true,  isAdjacentTrip: false, adjacentTripLabel: nil, isPast: false, delayMinutes: nil),
        .init(id: "4", stopName: "LAST STOP TERMINAL",      arrivalTime: "10:25 PM", segment: .last,   routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: false, delayMinutes: nil),
        .init(id: "5", stopName: "Continues as SIM34",      arrivalTime: "", segment: .adjacentNext, routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: true,  adjacentTripLabel: "Continues as", isPast: false, delayMinutes: nil),
    ]

    TripStopListView(
        header: header,
        stops: stops,
        onSelectStop: { _ in },
        serviceAlerts: ["Route SIM33C is experiencing delays due to traffic on Church St."]
    )
    .preferredColorScheme(.dark)
}

#Preview("Empty state") {
    TripStopListView(
        header: TripPanelHeaderViewModel(
            routeHeadsign: "Loading…",
            scheduledTime: "", statusText: "",
            minutesUntilArrival: nil, isRealTime: false
        ),
        stops: [],
        onSelectStop: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
