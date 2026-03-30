//
//  RecentStopsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - ViewModel

@MainActor
final class RecentStopsViewModel: ObservableObject {
    @Published var alarms: [AlarmRow] = []
    @Published var stops: [StopRow] = []
    @Published var isLoadingDeepLink = false
    @Published var errorMessage: String?

    private let application: Application

    struct AlarmRow: Identifiable {
        let id: URL
        let title: String
        let alarm: Alarm
        let deepLink: ArrivalDepartureDeepLink
    }

    struct StopRow: Identifiable {
        let id: String   // stop.id
        let name: String
        let subtitle: String?
        let routeType: Route.RouteType
        let stop: Stop
    }

    init(application: Application) {
        self.application = application
    }

    func reload() {
        application.userDataStore.deleteExpiredAlarms()

        let currentRegion = application.currentRegion

        alarms = application.userDataStore.alarms.compactMap { alarm in
            guard let deepLink = alarm.deepLink else { return nil }
            return AlarmRow(id: alarm.url, title: deepLink.title, alarm: alarm, deepLink: deepLink)
        }

        stops = application.userDataStore.recentStops
            .filter { $0.regionIdentifier == currentRegion?.regionIdentifier }
            .map { stop in
                StopRow(
                    id: stop.id,
                    name: stop.name,
                    subtitle: stop.subtitle,
                    routeType: stop.prioritizedRouteTypeForDisplay,
                    stop: stop
                )
            }
    }

    func deleteAllStops() {
        application.userDataStore.deleteAllRecentStops()
        reload()
    }

    func delete(stop: StopRow) {
        application.userDataStore.delete(recentStop: stop.stop)
        reload()
    }

    func delete(alarm: AlarmRow) {
        Task {
            try? await application.obacoService?.deleteAlarm(url: alarm.alarm.url)
        }
        application.userDataStore.delete(alarm: alarm.alarm)
        reload()
    }

    func selectAlarm(_ alarm: AlarmRow, from vc: UIViewController) {
        Task(priority: .userInitiated) {
            guard let apiService = application.apiService else { return }
            isLoadingDeepLink = true
            defer { isLoadingDeepLink = false }
            do {
                let dl = alarm.deepLink
                let response = try await apiService.getTripArrivalDepartureAtStop(
                    stopID: dl.stopID,
                    tripID: dl.tripID,
                    serviceDate: dl.serviceDate,
                    vehicleID: dl.vehicleID,
                    stopSequence: dl.stopSequence)
                application.viewRouter.navigateTo(arrivalDeparture: response.entry, from: vc)
            } catch {
                await application.displayError(error)
            }
        }
    }

    func selectStop(_ stop: StopRow, from vc: UIViewController) {
        application.viewRouter.navigateTo(stopID: stop.id, from: vc)
    }

    func navigateToMap() {
        application.viewRouter.rootNavigateTo(page: .map)
    }
}

// MARK: - SwiftUI View

struct RecentStopsView: View {
    @ObservedObject var viewModel: RecentStopsViewModel
    /// Passed directly — avoids weak/unowned issues in SwiftUI structs.
    var hostViewController: UIViewController?
    var application: Application?

    var body: some View {
        Group {
            if viewModel.alarms.isEmpty && viewModel.stops.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .overlay {
            if viewModel.isLoadingDeepLink {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear { viewModel.reload() }
    }

    // MARK: - List

    private var list: some View {
        List {
            if !viewModel.alarms.isEmpty {
                Section(OBALoc("recent_stops_controller.alarms_section.title",
                               value: "Alarms",
                               comment: "Title of the Alarms section of the Recents controller")) {
                    ForEach(viewModel.alarms) { alarm in
                        Button {
                            guard let vc = hostViewController else { return }
                            viewModel.selectAlarm(alarm, from: vc)
                        } label: {
                            Label(alarm.title, systemImage: "bell")
                                .foregroundStyle(.primary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.delete(alarm: alarm)
                            } label: {
                                Label(Strings.delete, systemImage: "trash")
                            }
                        }
                        .accessibilityLabel(alarm.title)
                        .accessibilityHint(OBALoc("voiceover.recent_stops.alarm_hint",
                                                  value: "Tap to view trip details",
                                                  comment: "VoiceOver hint for alarm rows in Recent Stops."))
                    }
                }
            }

            if !viewModel.stops.isEmpty {
                if viewModel.alarms.isEmpty {
                    Section {
                        stopsRows
                    }
                } else {
                    Section(Strings.recentStops) {
                        stopsRows
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { viewModel.reload() }
    }

    @ViewBuilder
    private var stopsRows: some View {
        ForEach(viewModel.stops) { stop in
            Button {
                guard let vc = hostViewController else { return }
                viewModel.selectStop(stop, from: vc)
            } label: {
                StopRowView(stop: stop)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    viewModel.delete(stop: stop)
                } label: {
                    Label(Strings.delete, systemImage: "trash")
                }
            }
            .contextMenu {
                Button(role: .destructive) {
                    viewModel.delete(stop: stop)
                } label: {
                    Label(Strings.delete, systemImage: "trash")
                }
            } preview: {
                RecentStopPreviewRepresentable(
                    application: application,
                    stopID: stop.id
                )
            }
            .accessibilityLabel(stop.name)
            .accessibilityValue(stop.subtitle ?? "")
            .accessibilityHint(OBALoc("voiceover.recent_stops.stop_hint",
                                      value: "Tap to view stop arrivals",
                                      comment: "VoiceOver hint for stop rows in Recent Stops."))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(OBALoc("recent_stops.empty_set.title",
                        value: "No Recent Stops",
                        comment: "Title for the empty set indicator on the Recent Stops controller."))
                .font(.title2.bold())

            Text(OBALoc("recent_stops.empty_set.body",
                        value: "Transit stops that you view in the app will appear here.",
                        comment: "Body for the empty set indicator on the Recent Stops controller."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(OBALoc("recent_stops.empty_set.button",
                          value: "Find Stops on Maps",
                          comment: "The button title for taking the user to the map view to find stops.")) {
                viewModel.navigateToMap()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Stop Row subview

private struct StopRowView: View {
    let stop: RecentStopsViewModel.StopRow

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .foregroundStyle(.primary)
                if let subtitle = stop.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            let icon = Icons.transportIcon(from: stop.routeType)
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Stop peek preview for context menu

private struct RecentStopPreviewRepresentable: UIViewControllerRepresentable {
    let application: Application?
    let stopID: StopID

    func makeUIViewController(context: Context) -> UIViewController {
        guard let app = application else { return UIViewController() }
        return StopViewController(application: app, stopID: stopID)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}


