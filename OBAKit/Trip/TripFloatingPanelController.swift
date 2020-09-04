//
//  TripDetailsController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import OBAKitCore
import FloatingPanel

/// Displays a list of stops for the trip corresponding to an `ArrivalDeparture` object.
class TripFloatingPanelController: UIViewController,
    AppContext,
    ListAdapterDataSource,
    SectionDataBuilders,
    ViewRouterDelegate {

    let application: Application

    var tripDetails: TripDetails? {
        didSet {
            if isLoadedAndOnScreen {
                collectionController.reload(animated: false)
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
    weak var tripDetailsOperation: NetworkOperation? {
        didSet {
            self.progressView.observedProgress = tripDetailsOperation!.progress
        }
    }

    private let operation: DecodableOperation<RESTAPIResponse<TripDetails>>?

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
        self.operation = nil

        super.init(nibName: nil, bundle: nil)
    }

    /// Initializes the `TripDetailsController` with an OBA application object and an in-flight model operation.
    /// - Parameter application: The application object
    /// - Parameter operation: An operation that will result in a `TripDetails` object that can be used to finish configuring this controller.
    init(application: Application, operation: DecodableOperation<RESTAPIResponse<TripDetails>>) {
        self.application = application
        self.operation = operation

        super.init(nibName: nil, bundle: nil)

        self.operation?.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.application.displayError(error)
            case .success(let response):
                self.tripDetails = response.entry
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        operation?.cancel()
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        prepareChildController(collectionController) {
            view.addSubview(outerStack)
            outerStack.pinToSuperview(.edges)
        }
    }

    // MARK: - Public Methods

    public func highlightStopInList(_ stop: Stop) {
        var listItem: TripStopListItem?

        for obj in collectionController.listAdapter.objects() {
            if let obj = obj as? TripStopListItem {
                if obj.stop.id == stop.id {
                    listItem = obj
                    break
                }
            }
        }

        if let listItem = listItem {
            collectionController.listAdapter.scroll(to: listItem, supplementaryKinds: nil, scrollDirection: .vertical, scrollPosition: .top, animated: true)
        }
    }

    public func configureView(for drawerPosition: FloatingPanelPosition) {
        switch drawerPosition {
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
        case .hidden: break
        @unknown default: break
        }
    }

    // MARK: - UI

    public lazy var collectionController: CollectionController = {
        let collection = CollectionController(application: application, dataSource: self)
        collection.collectionView.showsVerticalScrollIndicator = false

        return collection
    }()

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

    public lazy var progressView = UIProgressView.autolayoutNew()

    private lazy var separatorView: UIView = {
        let view = UIView.autolayoutNew()
        view.backgroundColor = ThemeColors.shared.separator
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1.0)
        ])
        return view
    }()

    private lazy var outerStack = UIStackView.verticalStack(arrangedSubviews: [topPaddingView, stopArrivalWrapper, progressView, separatorView, collectionController.view])

    // MARK: - ViewRouterDelegate methods

    public func shouldNavigate(to destination: ViewRouter.NavigationDestination) -> Bool {
        // If the stop we want to navigate to is a stop in the current trip, let's
        // highlight and mark the stop on the map rather than navigate to a separate
        // view controller.

        guard
            let tripViewController = self.parentTripViewController,
            let tripDetails = self.tripDetails,
            case let .stop(destinationStop) = destination,
            let matchingStopTime = tripDetails.stopTimes.filter({ $0.stop == destinationStop }).first
        else {
            return true
        }

        tripViewController.selectedStopTime = matchingStopTime
        return false
    }

    // MARK: - ListAdapterDataSource (Data Loading)

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        guard let tripDetails = tripDetails else {
            return []
        }

        var sections = [ListDiffable]()

        // Section: Service Alerts
        if tripDetails.serviceAlerts.count > 0 {
            sections.append(contentsOf: buildServiceAlertsSections(alerts: tripDetails.serviceAlerts))
        }

        // Section: Previous Trip
        if let previousTrip = tripDetails.previousTrip {
            let section = AdjacentTripSection(trip: previousTrip, order: .previous) { [weak self] in
                self?.showAdjacentTrip(previousTrip)
            }
            sections.append(section)
        }

        // Section: Stop Times
        let arrivalDeparture = tripConvertible?.arrivalDeparture
        for stopTime in tripDetails.stopTimes {
            sections.append(TripStopListItem(stopTime: stopTime, arrivalDeparture: arrivalDeparture, formatters: application.formatters))
        }

        // Section: Next Trip
        if let nextTrip = tripDetails.nextTrip {
            let section = AdjacentTripSection(trip: nextTrip, order: .next) { [weak self] in
                self?.showAdjacentTrip(nextTrip)
            }
            sections.append(section)
        }

        return sections
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    private func showAdjacentTrip(_ trip: Trip) {
        guard
            let apiService = application.restAPIService,
            let tripDetails = tripDetails
        else { return }

        let op = apiService.getTrip(tripID: trip.id, vehicleID: tripDetails.status?.vehicleID, serviceDate: tripDetails.serviceDate)
        let controller = TripFloatingPanelController(application: self.application, operation: op)
        self.application.viewRouter.navigate(to: controller, from: self)
    }

    private func buildServiceAlertsSections(alerts: [ServiceAlert]) -> [ListDiffable] {
        var sections = [ListDiffable]()
        sections.append(sectionData(from: alerts, collapsedState: .alwaysExpanded))
        sections.append(TableHeaderData(title: OBALoc("trip_details_controller.service_alerts_footer", value: "Trip Details", comment: "Service alerts header in the trip details controller. Cleverly, it looks like the header for the next section.")))

        return sections
    }
}
