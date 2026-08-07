//
//  StopDetailsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore
import ActivityKit

/// Thin hosting wrapper for `StopDetailsSheetView`. Its only job is to apply
/// `.defaultAppStorage` so the sheet's `@AppStorage` reads and writes the
/// app-group suite (matching the pushed page and the view model) rather than
/// `UserDefaults.standard` — the same job `StopPageRootView` does for the pushed
/// presentation.
///
/// It has to be a separate view. `.defaultAppStorage(_:)` only reaches
/// `AppStorage` instances *below* the view it modifies; a view's own property
/// wrappers resolve against the environment it was handed, so the sheet applying
/// it inside its own body would leave its own `pastCollapsed` bound to
/// `UserDefaults.standard`. Expanding past departures on the map sheet would not
/// carry over to the pushed Stop page, and vice versa.
///
/// It deliberately does NOT observe `StopViewModel` — `StopDetailsSheetView`
/// remains the sole observer, and owns the `@StateObject`/`@State` that give the
/// view model and the presenter their lifetimes.
struct StopDetailsSheetRootView: View {
    /// Forwarded so the route this view was built for stays readable without
    /// instantiating the sheet, both in debug output and to the factory's tests.
    let stopID: StopID

    let makeViewModel: () -> StopViewModel
    let makePresenter: () -> StopPageActionPresenter
    let feedback: DataLoadFeedbackGenerator
    let formatters: Formatters
    let userDefaults: UserDefaults

    var body: some View {
        StopDetailsSheetView(
            stopID: stopID,
            viewModel: makeViewModel(),
            presenter: makePresenter(),
            feedback: feedback,
            formatters: formatters,
            userDefaults: userDefaults
        )
        .defaultAppStorage(userDefaults)
    }
}

/// The Stop page as a native SwiftUI sheet over the map panel.
///
/// It renders the same departures as the pushed screen — through the shared
/// `StopDeparturesSections` — but replaces the navigation bar with a pinned
/// Refresh/Close strip and a row of circular actions, and collapses the map
/// header away as the list scrolls so the actions stay reachable.
///
/// This is the only view here that observes `StopViewModel`; the header, the
/// action row and the sections all take plain values, so the view model's
/// refresh and status-timer churn re-evaluates one shallow body.
struct StopDetailsSheetView: View {
    /// The stop this sheet was built for. Stored rather than read off the view
    /// model because the model lives in a `@StateObject` that SwiftUI only
    /// instantiates at render time — this is what identifies the view before
    /// then, both in debug output and to the factory's tests.
    let stopID: StopID

    @StateObject private var viewModel: StopViewModel
    @EnvironmentObject private var coordinator: SheetCoordinator<AppSheetRoute>
    /// Feeds `snapshotTraits`. `UITraitCollection.current` is only guaranteed to
    /// be the view's own traits inside `traitCollectionDidChange`,
    /// `layoutSubviews` or `draw(_:)`; the header's snapshot is loaded from a
    /// `.task`, outside any UIKit update pass, where reading it can hand
    /// `MapSnapshotter` a `displayScale` of 1.0 on a 3x device and render a
    /// visibly soft map card.
    @Environment(\.displayScale) private var displayScale

    /// `@StateObject`, not a plain `let`, for the same reason `viewModel` is
    /// one: `MapPanelRootView.body` re-evaluates on every map camera update,
    /// annotation change and detent write-back, and each pass rebuilds this view
    /// from the factory. Every modal the presenter opens holds it **weakly**
    /// (`StopPreferencesWrappedView`, `AddBookmarkViewController`,
    /// `EditBookmarkViewController`, `AlarmBuilder`), so a presenter replaced
    /// mid-flow takes Save on the route filter, Cancel on the bookmark editor
    /// and the alarm confirmation down with it. This keeps the first one for the
    /// life of the sheet.
    ///
    /// `@StateObject` rather than `@State` because only its `wrappedValue` is an
    /// autoclosure. `State(wrappedValue:)` takes a plain value, so the factory
    /// ran eagerly in `init` on every one of those parent passes and the result
    /// was thrown away — correct, but wasted allocation on a hot path.
    @StateObject private var presenter: StopPageActionPresenter
    private let feedback: DataLoadFeedbackGenerator
    private let formatters: Formatters
    private let userDefaults: UserDefaults

    @State private var expandedRouteID: RouteID?
    @State private var donationHidden = false
    /// How far the title has faded into the pinned bar, 0...1. Drives opacity
    /// ONLY — never layout. See the note on `titleFadeDistance`.
    @State private var titleProgress: CGFloat = 0
    /// Distance scrolled from the top. Drives the action row's overlay position
    /// and the title fade — never any layout the scroll view can observe.
    @State private var scrollOffset: CGFloat = 0
    /// Measured heights feeding the sticky-overlay arithmetic. None of them
    /// depend on `scrollOffset`, which is what keeps the overlay acyclic.
    @State private var topBarHeight: CGFloat = 0
    @State private var mapCardHeight: CGFloat = 0
    @State private var actionRowHeight: CGFloat = 0
    /// The scroll view's container height, used to decide when the rider has
    /// scrolled far enough to offer a way back. Read-only, like `scrollOffset` —
    /// nothing derived from it affects layout.
    @State private var viewportHeight: CGFloat = 0
    @State private var userActivity: NSUserActivity?
    /// Gates the one-shot success haptic to the first arrivals load, matching
    /// `StopViewController.bindArrivalsSink()`; later refreshes are silent.
    @State private var firstLoad = true
    /// Drives the top bar's spinner. Distinct from `viewModel.isLoading`, which
    /// also flips for the ~15s background refresh — the rider did not ask for
    /// that one, so it should not flash chrome at them.
    @State private var isManuallyRefreshing = false

    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    init(
        stopID: StopID,
        viewModel: @autoclosure @escaping () -> StopViewModel,
        presenter: @autoclosure @escaping () -> StopPageActionPresenter,
        feedback: DataLoadFeedbackGenerator,
        formatters: Formatters,
        userDefaults: UserDefaults
    ) {
        self.stopID = stopID
        _viewModel = StateObject(wrappedValue: viewModel())
        _presenter = StateObject(wrappedValue: presenter())
        self.feedback = feedback
        self.formatters = formatters
        self.userDefaults = userDefaults
    }

    /// Built once per body evaluation and threaded down, rather than computed.
    ///
    /// The handler is a 17-field struct of freshly-allocated closures wrapping
    /// three more closure structs. As a computed property the chrome, the header
    /// and the departures list rebuilt it ten times per pass — on a screen the
    /// view model republishes on a per-second status timer — and every closure
    /// identity changed each time, so nothing downstream could diff as equal.
    private func makeNavigation() -> StopPageNavigationHandler {
        presenter.makeNavigationHandler(viewModel: viewModel, closeSheet: { coordinator.pop() })
    }

    // MARK: - Body

    var body: some View {
        // `ScrollViewReader` is a passthrough container: it hands out a proxy and
        // takes no part in layout, so it cannot feed scroll geometry back into
        // the list.
        ScrollViewReader { proxy in
            sheetBody(proxy: proxy)
        }
    }

    private func sheetBody(proxy: ScrollViewProxy) -> some View {
        let content = StopPageContent(viewModel: viewModel)
        let navigation = makeNavigation()

        return list(content: content, navigation: navigation)
            .listStyle(.plain)
            // No `.refreshable`: this presentation refreshes from the top bar's
            // button only, which is why that button stays pinned.
            //
            // Scroll position drives the title's OPACITY and the action row's
            // overlay position — never the height of the `safeAreaInset` below.
            // An inset whose height depends on scroll position feeds back on
            // itself: measured on device, collapsing a 170pt header shifted
            // `contentOffset.y + contentInsets.top` by exactly 170, so the metric
            // is not inset-invariant and any mid-range progress oscillates
            // (progress -> inset -> offset -> progress) until the main thread is
            // pegged and the whole app stops responding.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                track(scrollOffset: offset)
            }
            // A second, separate observation so each stays single-purpose. Like
            // the offset above it is read-only: it feeds a predicate and an
            // overlay, never layout.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in
                viewportHeight = height
            }
            // Fixed height — it holds only the top bar, so nothing here resizes
            // as the list scrolls.
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            // The action row rides as an overlay rather than list content or a
            // second inset. An overlay takes no part in the list's layout, so its
            // position can track scrolling without the scroll view ever observing
            // the result — the property the collapsing header lacked.
            .overlay(alignment: .top) { actionRowOverlay(navigation: navigation) }
            // Bottom-trailing overlay, for the same reason the action row is an
            // overlay: it takes no part in the list's layout, so it cannot feed
            // back into scroll geometry.
            .overlay(alignment: .bottomTrailing) { scrollToTopOverlay(proxy: proxy) }
            // A CONSTANT margin so the button never permanently covers the
            // footer's attribution line. It must not depend on the button's
            // visibility — layout driven by scroll position is what hung the app.
            .contentMargins(.bottom, Self.scrollToTopClearance, for: .scrollContent)
            .stopPageLifecycle(
                viewModel: viewModel,
                userDefaults: userDefaults,
                liveActivityStarted: viewModel.liveActivityStarted
            )
            .keepsScreenAwake()
            .environment(\.obaFormatters, formatters)
            .onChange(of: content.routeIDs) { _, ids in reconcileExpandedRoute(against: ids) }
            .refreshesOnForeground(
                onForeground: { Task { await viewModel.start() } },
                onBackground: { viewModel.deactivate() }
            )
            .onReceive(viewModel.$stop.compactMap { $0 }, perform: publishUserActivity(for:))
            .onReceive(viewModel.$stopArrivals.compactMap { $0 }) { _ in signalFirstLoad() }
            .onReceive(viewModel.$operationError.compactMap { $0 }) { _ in feedback.dataLoad(.failed) }
            .onReceive(viewModel.presentFullSurvey, perform: showFullSurvey(_:))
            .onReceive(viewModel.surveySubmissionError, perform: presenter.showError)
            .onReceive(viewModel.$alarmError.compactMap { $0 }, perform: presenter.showError)
            .onReceive(viewModel.$alarmPermissionDenied.dropFirst().filter { $0 }) { _ in
                showAlarmPermissionDenied()
            }
            .onDisappear(perform: invalidateUserActivity)
    }

    // MARK: - Content

    private func list(content: StopPageContent, navigation: StopPageNavigationHandler) -> some View {
        List {
            headerRows(showsLoadingState: content.showsLoadingState, navigation: navigation)
            departures(content: content, navigation: navigation)
        }
    }

    /// The shared assembly of the departures list. Identical to the one the
    /// pushed page builds apart from `onRetry`: this presentation has no
    /// pull-to-refresh, so a retry goes through the same spinner-floored path as
    /// the top bar's button.
    private func departuresBuilder(navigation: StopPageNavigationHandler) -> StopDeparturesBuilder {
        StopDeparturesBuilder(
            viewModel: viewModel,
            navigation: navigation,
            userDefaults: userDefaults,
            onRetry: refresh,
            expandedRouteID: $expandedRouteID,
            donationHidden: $donationHidden,
            pastCollapsed: $pastCollapsed
        )
    }

    private func departures(content: StopPageContent, navigation: StopPageNavigationHandler) -> some View {
        departuresBuilder(navigation: navigation).sections(content: content, walkTime: viewModel.walkTime)
    }

    // MARK: - List actions

    /// A warm refresh usually resolves in well under a frame, so the spinner
    /// would appear and vanish before the eye caught it — reading as "the button
    /// did nothing". Hold it for a floor so the tap always has a visible result.
    private func refresh() {
        guard !isManuallyRefreshing else { return }
        // Set before the `Task`, not inside it. The guard reads synchronously
        // but the task body resumes after a hop, so two taps landing in the
        // same runloop turn would both clear a guard neither had set yet —
        // two refreshes, two spinner floors, racing to reset one flag.
        // `.disabled(isRefreshing)` narrows that window but does not close it:
        // SwiftUI has not re-rendered the button yet.
        isManuallyRefreshing = true

        Task {
            let started = ContinuousClock.now
            await viewModel.refresh()

            let elapsed = ContinuousClock.now - started
            if elapsed < Self.minimumSpinnerDuration {
                try? await Task.sleep(for: Self.minimumSpinnerDuration - elapsed)
            }
            isManuallyRefreshing = false
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo(Self.topRowID, anchor: .top)
        }
    }

    // MARK: - Side effects

    private func track(scrollOffset offset: CGFloat) {
        scrollOffset = offset
        titleProgress = StopSheetTitleFade.progress(
            scrollOffset: offset,
            fadeDistance: Self.titleFadeDistance
        )
    }

    private func reconcileExpandedRoute(against ids: Set<RouteID>) {
        if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
    }

    private func publishUserActivity(for stop: Stop) {
        userActivity?.invalidate()
        let activity = presenter.makeUserActivity(stop: stop)
        activity?.becomeCurrent()
        userActivity = activity
    }

    private func invalidateUserActivity() {
        userActivity?.invalidate()
        userActivity = nil
    }

    /// The success haptic fires on the first arrivals load only; later refreshes
    /// are silent.
    private func signalFirstLoad() {
        guard firstLoad else { return }
        firstLoad = false
        feedback.dataLoad(.success)
    }

    private func showFullSurvey(_ payload: StopViewModel.FullSurveyPresentation) {
        presenter.showFullSurvey(
            payload.survey,
            heroResponseID: payload.heroResponseID,
            stop: viewModel.stop,
            stopID: viewModel.stopID
        )
    }

    private func showAlarmPermissionDenied() {
        presenter.showAlarmPermissionDeniedAlert {
            // Reset so a later already-denied attempt re-fires the binding.
            viewModel.clearAlarmPermissionDenied()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        StopDetailsSheetTopBar(
            title: viewModel.stop?.name ?? "",
            titleOpacity: Double(titleProgress),
            statusText: viewModel.statusText,
            isRefreshing: isManuallyRefreshing,
            onRefresh: refresh,
            onClose: { coordinator.pop() }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
    }

    /// Distance scrolled, in points, over which the stop name fades into the
    /// pinned bar. A plain constant: it drives opacity only, so it never needs
    /// to match the header's real height, and keeping it out of layout is what
    /// makes the fade safe.
    private static let titleFadeDistance: CGFloat = 120

    /// How long the refresh spinner stays up at minimum.
    private static let minimumSpinnerDuration: Duration = .milliseconds(600)

    /// The map card, plus a spacer standing in for the action row.
    ///
    /// The action row itself is an overlay (see `actionRowOverlay`), so the list
    /// needs a gap of the same height here or the first departures would sit
    /// underneath it at rest.
    @ViewBuilder
    private func headerRows(showsLoadingState: Bool, navigation: StopPageNavigationHandler) -> some View {
        Section {
            Group {
                if let stop = viewModel.stop {
                    StopPageHeaderView(
                        stop: stop,
                        walkTime: viewModel.walkTime,
                        statusText: viewModel.statusText,
                        snapshotLoader: { size in
                            await presenter.loadSnapshot(stop: stop, size: size, traitCollection: snapshotTraits)
                        },
                        onWalkingDirections: navigation.showWalkingDirections
                    )
                } else if showsLoadingState {
                    StopPageHeaderPlaceholderView()
                }
            }
            // Safe to measure: the card's height is a function of Dynamic Type
            // and how many route chips wrap, never of scroll position.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapCardHeight = $0 }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Color.clear
                .frame(height: actionRowHeight)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
        // The scroll-to-top target. The id belongs on the Section: a row-level id
        // does not resolve for `ScrollViewReader` in this List. It rides the
        // existing header rather than a zero-height sentinel row, which would pick
        // up the List's minimum row height and leave a visible gap.
        .id(Self.topRowID)
    }

    /// The traits the header's map snapshot renders at.
    ///
    /// `displayScale` is the one that matters: `MapSnapshotter` hands it to
    /// `MKMapSnapshotter.Options` and to the stop-icon factory, so getting it
    /// wrong is the difference between a crisp card and a blurry one. The
    /// interface style is not derived here — `loadSnapshot` forces dark, because
    /// the header is always-dark by design.
    private var snapshotTraits: UITraitCollection {
        UITraitCollection { traits in
            traits.displayScale = displayScale
        }
    }

    /// Where the action row sits, measured from the top of the sheet.
    ///
    /// At rest it clears the top bar and the map card, putting it directly under
    /// the card. As the list scrolls it rises until it reaches the bar, then
    /// stops — the card slides beneath it. Rubber-banding past the top yields a
    /// negative `scrollOffset`, which pushes the row further down with the
    /// stretch, which is the natural behaviour.
    private var actionRowOffset: CGFloat {
        topBarHeight + max(0, mapCardHeight - scrollOffset)
    }

    private func actionRowOverlay(navigation: StopPageNavigationHandler) -> some View {
        StopPageActionRow(
            state: StopPageActionRowState(
                hasStop: viewModel.stop != nil,
                routeCount: viewModel.stop?.routes.count ?? 0,
                hasHiddenRoutes: viewModel.stopPreferences.hasHiddenRoutes,
                isListFiltered: viewModel.isListFiltered,
                hasServiceAlerts: !(viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty
            ),
            onSchedule: navigation.showScheduleForStop,
            onSetListFiltered: { filtered in
                viewModel.isListFiltered = filtered
                // Picking "Filtered Routes" opens the picker, matching the
                // pushed presentation's `filterMenu()` — otherwise choosing it
                // on a stop with no saved hidden routes silently does nothing.
                if filtered { navigation.showRouteFilter() }
            },
            onBookmark: { navigation.showBookmarkEditor(nil) },
            onServiceAlerts: navigation.showServiceAlerts,
            onNearbyStops: navigation.showNearbyStops,
            onWalkingDirections: navigation.showWalkingDirections,
            onReportProblem: navigation.showReportProblem
        )
        // Feeds the spacer above, so the two stay the same height as Dynamic
        // Type changes.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionRowHeight = $0 }
        .offset(y: actionRowOffset)
    }

    /// Space reserved at the end of the list so the floating button does not sit
    /// permanently on top of the attribution line. Constant by design.
    private static let scrollToTopClearance: CGFloat = 72

    /// Identifies the header section so `ScrollViewReader` can scroll back to it.
    private static let topRowID = "stop-details-top"

    private var showsScrollToTop: Bool {
        ScrollToTopVisibility.shouldShow(scrollOffset: scrollOffset, viewportHeight: viewportHeight)
    }

    private func scrollToTopOverlay(proxy: ScrollViewProxy) -> some View {
        ScrollToTopButton(isVisible: showsScrollToTop) { scrollToTop(proxy: proxy) }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
            .animation(.snappy(duration: 0.2), value: showsScrollToTop)
    }
}
