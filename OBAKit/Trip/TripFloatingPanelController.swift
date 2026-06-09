//
//  TripDetailsController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import FloatingPanel

// MARK: - TripProgressViewModel

/// Testable value type encapsulating the "Stop X of Y" header data.
/// Returns `nil` when progress data is unavailable and the header should be hidden.
struct TripProgressViewModel {
    let stopCountText: String
    let etaText: String?
    let progress: Float

    init?(closestStopIndex: Int, totalStops: Int, userStopIndex: Int?, arrivalDepartureMinutes: Int?) {
        guard totalStops > 0 else { return nil }
        let currentStopNumber = closestStopIndex + 1
        progress = Float(currentStopNumber) / Float(totalStops)
        stopCountText = String(
            format: OBALoc(
                "trip_progress.stop_count_fmt",
                value: "Stop %1$d of %2$d",
                comment: "Shows the current stop position. e.g. Stop 5 of 18"
            ),
            currentStopNumber, totalStops
        )
        if let userStopIndex {
            if userStopIndex < closestStopIndex {
                etaText = OBALoc(
                    "trip_progress.passed_your_stop",
                    value: "Passed your stop",
                    comment: "Shown when the vehicle has already passed the user's destination stop"
                )
            } else if userStopIndex == closestStopIndex {
                etaText = OBALoc(
                    "trip_progress.arriving_now",
                    value: "Arriving now",
                    comment: "Shown when the vehicle is arriving at the user's stop"
                )
            } else if let minutes = arrivalDepartureMinutes, minutes > 0 {
                etaText = String(
                    format: OBALoc(
                        "trip_progress.eta_to_stop_fmt",
                        value: "~%d min to your stop",
                        comment: "Estimated time of arrival to the user's stop. e.g. ~8 min to your stop"
                    ),
                    minutes
                )
            } else {
                etaText = OBALoc(
                    "trip_progress.arriving_now",
                    value: "Arriving now",
                    comment: "Shown when the vehicle is arriving at the user's stop"
                )
            }
        } else {
            etaText = nil
        }
    }
}

// MARK: -

/// Displays a list of stops for the trip corresponding to an `ArrivalDeparture` object.
class TripFloatingPanelController: UIViewController,
    AppContext,
    OBAListViewDataSource,
    OBAListViewCollapsibleSectionsDelegate,
    OBAListViewContextMenuDelegate {

    let application: Application

    var tripDetails: TripDetails? {
        didSet {
            if isLoadedAndOnScreen {
                listView.applyData(animated: false)
                updateProgressView()
            }
        }
    }

    var tripConvertible: TripConvertible? {
        didSet {
            if isLoadedAndOnScreen, let arrivalDeparture = tripConvertible?.arrivalDeparture {
                stopArrivalView.arrivalDeparture = arrivalDeparture
            }
        }
    }

    weak var parentTripViewController: TripViewController?

    /// Tracks whether the floating panel is expanded enough to show the progress header.
    /// Combined with data availability in `updateProgressView` to give `tripProgressWrapper`
    /// a single source of truth for its hidden state.
    private var isPanelExpandedEnoughForProgress = false

    // MARK: - Init/Deinit

    /// Initializes the `TripDetailsController` with an OBA application object.
    /// - Parameter application: The application object
    /// - Parameter tripConvertible: Optional `TripConvertible` object.
    /// - Parameter parentTripViewController: Optional `TripViewController`.
    ///
    /// It is assumed that the creator of this controller will pass in a `TripDetails` object via
    /// the `tripDetails` property later on in order to finish configuring this controller.
    init(application: Application, tripConvertible: TripConvertible? = nil, parentTripViewController: TripViewController? = nil) {
        self.application = application
        self.tripConvertible = tripConvertible
        self.parentTripViewController = parentTripViewController

        super.init(nibName: nil, bundle: nil)
    }

    /// Initializes the `TripDetailsController` with an OBA application object.
    /// - Parameter application: The application object
    /// - Parameter tripDetails: The `TripDetails` object to display.
    init(application: Application, tripDetails: TripDetails) {
        self.application = application
        self.tripDetails = tripDetails

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        listView.formatters = application.formatters
        listView.obaDataSource = self
        listView.collapsibleSectionsDelegate = self
        listView.contextMenuDelegate = self
        listView.register(listViewItem: TripStopViewModel.self)

        view.backgroundColor = ThemeColors.shared.systemBackground
        view.addSubview(outerStack)
        outerStack.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        listView.applyData(animated: false)
        updateProgressView()
    }

    // MARK: - Public Methods
    public func highlightStopInList(_ matchingStop: Stop) {
        let data = self.items(for: listView)

        var matchingIndexPath: IndexPath?
        for (sectionIndex, section) in data.enumerated() {
            for (itemIndex, item) in section.contents.enumerated() {
                guard let tripStop = item.as(TripStopViewModel.self),
                      tripStop.stop.id == matchingStop.id else { continue }
                matchingIndexPath = IndexPath(item: itemIndex, section: sectionIndex)
                break
            }
        }

        if let matchingIndexPath = matchingIndexPath {
            listView.scrollToItem(at: matchingIndexPath, at: .top, animated: true)

            // There's no completionHandler for scrollToItem, so just wait 3/4 of
            // a second for scrolling to hopefully finish.
            // Note: If 750ms passes, but the cell is still not visible, then the `blink` won't appear.
            DispatchQueue.main.throttle(deadline: .now() + .milliseconds(750)) { [weak self] in
                (self?.listView.cellForItem(at: matchingIndexPath) as? OBAListViewCell)?.blink()
            }
        }
    }

    public func configureView(for panelState: FloatingPanelState) {
        switch panelState {
        case .tip:
            self.separatorView.isHidden = true
            self.isPanelExpandedEnoughForProgress = false
            self.stopArrivalView.normalInfoStack.forEach { $0.isHidden = isAccessibility }
            self.stopArrivalView.accessibilityInfoStack.forEach { $0.isHidden = true }
        case .half:
            self.separatorView.isHidden = false
            self.isPanelExpandedEnoughForProgress = true
            self.stopArrivalView.normalInfoStack.forEach { $0.isHidden = isAccessibility }
            self.stopArrivalView.accessibilityInfoStack.forEach { $0.isHidden = true }
            self.stopArrivalView.accessibilityMinimalInfoStack.forEach { $0.isHidden = !isAccessibility }
        case .full:
            self.separatorView.isHidden = false
            self.isPanelExpandedEnoughForProgress = true
            self.stopArrivalView.normalInfoStack.forEach { $0.isHidden = isAccessibility }
            self.stopArrivalView.accessibilityInfoStack.forEach { $0.isHidden = !isAccessibility }
        case .hidden:
            self.isPanelExpandedEnoughForProgress = false
        default: break
        }
        updateProgressView()
    }

    public func setListVisibility(isVisible: Bool) {
        listView.alpha = isVisible ? 1.0 : 0.0
    }

    // MARK: - UI
    var listView = OBAListView()
    private static let ServiceAlertsSectionID = "service_alerts"

    var collapsedSections: Set<OBAListViewSection.ID> = []
    var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = UISelectionFeedbackGenerator()

    private lazy var stopArrivalView: StopArrivalView = {
        let view = StopArrivalView.autolayoutNew()
        view.formatters = application.formatters
        if let arrDep = tripConvertible?.arrivalDeparture {
            view.arrivalDeparture = arrDep
        }
        return view
    }()

    private lazy var stopArrivalWrapper: UIView = {
        let wrapper = stopArrivalView.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            stopArrivalView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: ThemeMetrics.padding),
            stopArrivalView.leadingAnchor.constraint(equalTo: wrapper.readableContentGuide.leadingAnchor),
            stopArrivalView.trailingAnchor.constraint(equalTo: wrapper.readableContentGuide.trailingAnchor),
            stopArrivalView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -ThemeMetrics.compactPadding)
        ])
        return wrapper
    }()

    private lazy var topPaddingView: UIView = {
        let view = UIView.autolayoutNew()
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: ThemeMetrics.floatingPanelTopInset)
        ])
        return view
    }()

    private lazy var separatorView: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = ThemeColors.shared.separator
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1.0)
        ])
        return view
    }()

    private lazy var tripProgressView: TripProgressView = TripProgressView.autolayoutNew()

    private lazy var tripProgressWrapper: UIView = {
        let wrapper = tripProgressView.embedInWrapperView(setConstraints: false)
        wrapper.isHidden = true
        NSLayoutConstraint.activate([
            tripProgressView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: ThemeMetrics.compactPadding),
            tripProgressView.leadingAnchor.constraint(equalTo: wrapper.readableContentGuide.leadingAnchor),
            tripProgressView.trailingAnchor.constraint(equalTo: wrapper.readableContentGuide.trailingAnchor),
            tripProgressView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -ThemeMetrics.compactPadding)
        ])
        return wrapper
    }()

    private lazy var outerStack = UIStackView.verticalStack(arrangedSubviews: [topPaddingView, stopArrivalWrapper, tripProgressWrapper, separatorView, listView])

    // MARK: - Helpers

    /// Returns the index of the vehicle's closest stop within the trip's stop list, or nil if unavailable.
    private func closestStopIndex(in tripDetails: TripDetails) -> Int? {
        guard let closestStopID = tripDetails.status?.closestStopID else { return nil }
        return tripDetails.stopTimes.firstIndex { $0.stopID == closestStopID }
    }

    // MARK: - ListAdapterDataSource (Data Loading)
    func canCollapseSection(_ listView: OBAListView, section: OBAListViewSection) -> Bool {
        return section.id == TripFloatingPanelController.ServiceAlertsSectionID
    }

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        guard let tripDetails = tripDetails else { return [] }

        var sections: [OBAListViewSection] = []

        if tripDetails.serviceAlerts.count > 0 {
            sections.append(serviceAlertsListSection(tripDetails.serviceAlerts))
        }

        sections.append(
            tripStopListSection(
                tripDetails: tripDetails,
                arrivalDeparture: tripConvertible?.arrivalDeparture,
                showHeader: !tripDetails.serviceAlerts.isEmpty))

        for idx in sections.indices {
            sections[idx].configuration.appearance = .plain
        }

        return sections
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        return nil
    }

    private func onSelectAdjacentTrip(_ adjacentTrip: AdjacentTripItem) {
        guard
            let apiService = application.apiService,
            let tripDetails = tripDetails
        else { return }

        Task {
            ProgressHUD.show()

            do {
                let tripDetails = try await apiService.getTrip(tripID: adjacentTrip.trip.id, vehicleID: tripDetails.status?.vehicleID, serviceDate: tripDetails.serviceDate)

                await MainActor.run {
                    let controller = TripFloatingPanelController(application: application, tripDetails: tripDetails.entry)
                    self.application.viewRouter.navigate(to: controller, from: self)
                }
            } catch {
                await self.application.displayError(error)
            }

            ProgressHUD.dismiss()
        }
    }

    private func onSelectTripStop(_ tripStop: TripStopViewModel) {
        let transferContext = buildTransferContext(for: tripStop)
        application.viewRouter.navigateTo(stop: tripStop.stop, from: self, transferContext: transferContext)
    }

    private func buildTransferContext(for tripStop: TripStopViewModel) -> TransferContext? {
        guard let arrivalDeparture = tripConvertible?.arrivalDeparture else { return nil }

        // Only provide transfer context for stops that are not the user's
        // boarding stop — transferring to the same stop is not meaningful.
        guard tripStop.stop.id != arrivalDeparture.stopID else { return nil }

        return .from(arrivalDeparture: arrivalDeparture, arrivalDate: tripStop.stopTime.arrivalDate)
    }

    private func showOnMap(_ tripStop: TripStopViewModel) {
        parentTripViewController?.showStopOnMap(tripStop)
    }

    private func showOnList(_ tripStop: TripStopTime) {
        highlightStopInList(tripStop.stop)
    }

    private func serviceAlertsListSection(_ alerts: [ServiceAlert]) -> OBAListViewSection {
        let action: OBAListViewAction<TransitAlertDataListViewModel> = { [unowned self] viewModel in
            self.application.viewRouter.navigateTo(alert: viewModel.transitAlert, from: self)
        }

        let contents = alerts.map { TransitAlertDataListViewModel($0, forLocale: .current, onSelectAction: action) }

        // If there is more than one service alert, include the count of service alerts in the title.
        let title: String
        if contents.count == 1 {
            title = Strings.serviceAlert
        } else {
            title = "\(Strings.serviceAlerts) (\(contents.count))"
        }

        return OBAListViewSection(id: TripFloatingPanelController.ServiceAlertsSectionID, title: title, contents: contents)
    }

    private func tripStopListSection(tripDetails: TripDetails, arrivalDeparture: ArrivalDeparture?, showHeader: Bool) -> OBAListViewSection {
        var contents: [AnyOBAListViewItem] = []
        let selectAdjacentTripAction: OBAListViewAction<AdjacentTripItem> = { [unowned self] item in self.onSelectAdjacentTrip(item) }

        // Previous trip, if any.
        if let previousTrip = tripDetails.previousTrip {
            contents.append(AdjacentTripItem(order: .previous, trip: previousTrip, onSelectAction: selectAdjacentTripAction).typeErased)
        }

        let closestStopIdx = closestStopIndex(in: tripDetails)

        // Stop times
        let selectTripStopAction: OBAListViewAction<TripStopViewModel> = { [unowned self] item in self.onSelectTripStop(item) }
        let stopTimes: [AnyOBAListViewItem] = tripDetails.stopTimes.enumerated().map { index, stopTime in
            TripStopViewModel(
                stopTime: stopTime,
                arrivalDeparture: arrivalDeparture,
                stopIndex: index,
                closestStopIndex: closestStopIdx,
                onSelectAction: selectTripStopAction
            ).typeErased
        }
        contents.append(contentsOf: stopTimes)

        // Next trip, if any.
        if let nextTrip = tripDetails.nextTrip {
            contents.append(AdjacentTripItem(order: .next, trip: nextTrip, onSelectAction: selectAdjacentTripAction).typeErased)
        }

        let title: String? = showHeader ? OBALoc("trip_details_controller.service_alerts_footer", value: "Trip Details", comment: "Service alerts header in the trip details controller.") : nil
        return OBAListViewSection(id: "trip_stop_times", title: title, contents: contents)
    }

    // MARK: - Trip Progress

    private func updateProgressView() {
        guard
            isPanelExpandedEnoughForProgress,
            let tripDetails = tripDetails,
            let currentIndex = closestStopIndex(in: tripDetails)
        else {
            tripProgressWrapper.isHidden = true
            return
        }

        let arrivalDeparture = tripConvertible?.arrivalDeparture
        let userStopIndex = arrivalDeparture.flatMap { ad in
            tripDetails.stopTimes.firstIndex { $0.stopID == ad.stopID }
        }

        guard let vm = TripProgressViewModel(
            closestStopIndex: currentIndex,
            totalStops: tripDetails.stopTimes.count,
            userStopIndex: userStopIndex,
            arrivalDepartureMinutes: arrivalDeparture?.arrivalDepartureMinutes
        ) else {
            tripProgressWrapper.isHidden = true
            return
        }

        tripProgressView.configure(stopCountText: vm.stopCountText, etaText: vm.etaText, progress: vm.progress)
        tripProgressWrapper.isHidden = false
    }

    // MARK: - TripStop actions
    private func viewOnMapAction(for viewModel: TripStopViewModel) -> UIAction? {
        guard parentTripViewController != nil else { return nil }

        return UIAction(title: OBALoc("trip_details_controller.show_on_map", value: "Show on Map", comment: "Button that moves the map to focus on the selected stop"), image: UIImage(systemName: "mappin.circle")) { [unowned self] _ in
            self.showOnMap(viewModel)
        }
    }

    private func getWalkingDirections(for viewModel: TripStopViewModel) -> UIMenuElement? {
        let appleMapsAction: UIAction?
        if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: viewModel.stop.coordinate) {
            appleMapsAction = UIAction(title: OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop")) { [unowned self] _ in
                self.application.open(appleMapsURL, options: [:], completionHandler: nil)
            }
        } else {
            appleMapsAction = nil
        }

        let googleMapsAction: UIAction?
        #if !targetEnvironment(simulator)
        if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: viewModel.stop.coordinate) {
            googleMapsAction = UIAction(title: OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop")) { [unowned self] _ in
                self.application.open(googleMapsURL, options: [:], completionHandler: nil)
            }
        } else {
            googleMapsAction = nil
        }
        #else
        googleMapsAction = nil
        #endif

        let actions = [appleMapsAction, googleMapsAction].compactMap { $0 }
        guard !actions.isEmpty else { return nil }

        return UIMenu(title: OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop"), image: UIImage(systemName: "figure.walk"), children: actions)
    }

    var currentPreviewingViewController: UIViewController?
    func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        guard let tripStop = item.as(TripStopViewModel.self) else { return nil }

        let menu: OBAListViewMenuActions.MenuProvider = { [unowned self] _ -> UIMenu? in
            let menuActions = [
                self.viewOnMapAction(for: tripStop),
                self.getWalkingDirections(for: tripStop)
            ].compactMap { $0 }

            return UIMenu(title: tripStop.title, children: menuActions)
        }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { [unowned self] () -> UIViewController? in
            let stopVC = StopViewController(application: self.application, stopID: tripStop.stop.id)
            self.currentPreviewingViewController = stopVC
            return stopVC
        }

        let commitPreviewAction: VoidBlock = { [unowned self] in
            guard let vc = self.currentPreviewingViewController else { return }
            (vc as? Previewable)?.exitPreviewMode()
            self.application.viewRouter.navigate(to: vc, from: self)
        }

        return OBAListViewMenuActions(previewProvider: previewProvider, performPreviewAction: commitPreviewAction, contextMenuProvider: menu)
    }
}

// MARK: - TripProgressView

/// Displays trip progress as "Stop X of Y", an optional ETA label, and a thin progress bar.
final class TripProgressView: UIView {

    private let stopCountLabel: UILabel = {
        let label = UILabel.obaLabel(font: .preferredFont(forTextStyle: .caption1), textColor: ThemeColors.shared.secondaryLabel)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let etaLabel: UILabel = {
        let label = UILabel.obaLabel(font: .preferredFont(forTextStyle: .caption1), textColor: ThemeColors.shared.brand)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.textAlignment = .right
        return label
    }()

    private let progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.progressTintColor = ThemeColors.shared.brand
        bar.trackTintColor = ThemeColors.shared.separator
        bar.layer.cornerRadius = 1.5
        bar.clipsToBounds = true
        return bar
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let labelsStack = UIStackView(arrangedSubviews: [stopCountLabel, etaLabel])
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .horizontal
        labelsStack.spacing = ThemeMetrics.padding

        addSubview(labelsStack)
        addSubview(progressBar)

        NSLayoutConstraint.activate([
            labelsStack.topAnchor.constraint(equalTo: topAnchor),
            labelsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelsStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            progressBar.topAnchor.constraint(equalTo: labelsStack.bottomAnchor, constant: ThemeMetrics.compactPadding),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 3.0)
        ])

        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(stopCountText: String, etaText: String?, progress: Float) {
        stopCountLabel.text = stopCountText
        etaLabel.text = etaText
        etaLabel.isHidden = etaText == nil
        progressBar.setProgress(progress, animated: false)

        accessibilityLabel = [stopCountText, etaText].compactMap { $0 }.joined(separator: ". ")
    }
}
