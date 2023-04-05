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
            }
        }
    }

    var tripConvertible: TripConvertible? {
        didSet {
            if isLoadedAndOnScreen, let arrivalDeparture = stopArrivalView.arrivalDeparture {
                stopArrivalView.arrivalDeparture = arrivalDeparture
            }
        }
    }

    weak var parentTripViewController: TripViewController?

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
            self.stopArrivalView.normalInfoStack.forEach { $0.isHidden = isAccessibility }
            self.stopArrivalView.accessibilityInfoStack.forEach { $0.isHidden = true }
        case .half:
            self.separatorView.isHidden = false
            self.stopArrivalView.normalInfoStack.forEach { $0.isHidden = isAccessibility }
            self.stopArrivalView.accessibilityInfoStack.forEach { $0.isHidden = true }
            self.stopArrivalView.accessibilityMinimalInfoStack.forEach { $0.isHidden = !isAccessibility }
        case .full:
            self.separatorView.isHidden = false
            self.stopArrivalView.normalInfoStack.forEach { $0.isHidden = isAccessibility }
            self.stopArrivalView.accessibilityInfoStack.forEach { $0.isHidden = !isAccessibility }
        case .hidden: fallthrough
        default: break
        }
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

    private lazy var outerStack = UIStackView.verticalStack(arrangedSubviews: [topPaddingView, stopArrivalWrapper, separatorView, listView])

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
        application.viewRouter.navigateTo(stop: tripStop.stop, from: self)
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

        // Stop times
        let selectTripStopAction: OBAListViewAction<TripStopViewModel> = { [unowned self] item in self.onSelectTripStop(item) }
        let stopTimes: [AnyOBAListViewItem] = tripDetails.stopTimes.map { TripStopViewModel(stopTime: $0, arrivalDeparture: arrivalDeparture, onSelectAction: selectTripStopAction).typeErased }
        contents.append(contentsOf: stopTimes)

        // Next trip, if any.
        if let nextTrip = tripDetails.nextTrip {
            contents.append(AdjacentTripItem(order: .next, trip: nextTrip, onSelectAction: selectAdjacentTripAction).typeErased)
        }

        let title: String? = showHeader ? OBALoc("trip_details_controller.service_alerts_footer", value: "Trip Details", comment: "Service alerts header in the trip details controller.") : nil
        return OBAListViewSection(id: "trip_stop_times", title: title, contents: contents)
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
