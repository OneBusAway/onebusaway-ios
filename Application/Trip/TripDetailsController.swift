//
//  TripDetailsController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/4/19.
//

import UIKit
import IGListKit

/// Displays a list of stops for the trip corresponding to an `ArrivalDeparture` object.
public class TripDetailsController: UIViewController, ListProvider, ListAdapterDataSource, ModelViewModelConverters, AppContext {

    let application: Application

    var tripDetails: TripDetails? {
        didSet {
            if isLoadedAndOnScreen {
                collectionController.reload(animated: false)
            }
        }
    }

    var arrivalDeparture: ArrivalDeparture? {
        didSet {
            if isLoadedAndOnScreen {
                collectionController.reload(animated: false)
            }
        }
    }

    private let operation: TripDetailsModelOperation?

    // MARK: - Init/Deinit

    /// Initializes the `TripDetailsController` with an OBA application object.
    /// - Parameter application: The application object
    /// - Parameter arrivalDeparture: Optional `ArrivalDeparture` object.
    ///
    /// It is assumed that the creator of this controller will pass in a `TripDetails` object via
    /// the `tripDetails` property later on in order to finish configuring this controller.
    init(application: Application, arrivalDeparture: ArrivalDeparture? = nil) {
        self.application = application
        self.arrivalDeparture = arrivalDeparture
        self.operation = nil

        super.init(nibName: nil, bundle: nil)
    }

    /// Initializes the `TripDetailsController` with an OBA application object and an in-flight model operation.
    /// - Parameter application: The application object
    /// - Parameter operation: An operation that will result in a `TripDetails` object that can be used to finish configuring this controller.
    init(application: Application, operation: TripDetailsModelOperation) {
        self.application = application
        self.operation = operation

        super.init(nibName: nil, bundle: nil)

        self.operation?.then { [weak self] in
            guard let self = self else { return }
            self.tripDetails = self.operation?.tripDetails
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        operation?.cancel()
    }

    // MARK: - Collection Controller

    public lazy var collectionController = CollectionController(application: application, dataSource: self)

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    // MARK: - ListAdapterDataSource (Data Loading)

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        guard let tripDetails = tripDetails else {
            return []
        }

        var sections = [ListDiffable]()

        // Section: ArrivalDeparture Header

        if let arrivalDeparture = arrivalDeparture {
            sections.append(arrivalDeparture)
        }

        // Section: Previous Trip

        if let previousTrip = tripDetails.previousTrip {
            let titleFmt = NSLocalizedString("trip_details_controller.starts_as_fmt", value: "Starts as %@", comment: "Describes the previous trip of this vehicle. e.g. Starts as 10 - Downtown Seattle")
            sections.append(buildAdjacentTripSection(trip: previousTrip, rowTitleFormat: titleFmt))
        }

        // Section: Stop Times

        for stopTime in tripDetails.stopTimes {
            sections.append(TripStopListItem(stopTime: stopTime, arrivalDeparture: arrivalDeparture, formatters: application.formatters))
        }

        // Section: Next Trip

        if let nextTrip = tripDetails.nextTrip {
            let titleFmt = NSLocalizedString("trip_details_controller.continues_as_fmt", value: "Continues as %@", comment: "Describes the next trip of this vehicle. e.g. Continues as 10 - Downtown Seattle")
            sections.append(buildAdjacentTripSection(trip: nextTrip, rowTitleFormat: titleFmt))
        }

        return sections
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        if object is ArrivalDeparture {
            return StopArrivalSectionController(formatters: application.formatters)
        }
        else {
            let sectionController = defaultSectionController(for: object)
            sectionController.inset = .zero
            return sectionController
        }
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    private func buildAdjacentTripSection(trip: Trip, rowTitleFormat: String) -> TableSectionData {
        let rowTitle = String(format: rowTitleFormat, trip.routeHeadsign)
        let row = TableRowData(title: rowTitle, accessoryType: .disclosureIndicator) { [weak self] _ in
            guard
                let self = self,
                let apiService = self.application.restAPIModelService,
                let tripDetails = self.tripDetails
            else { return }

            let op = apiService.getTripDetails(tripID: trip.id, vehicleID: tripDetails.status?.vehicleID, serviceDate: tripDetails.serviceDate)
            let controller = TripDetailsController(application: self.application, operation: op)
            self.application.viewRouter.navigate(to: controller, from: self)
        }
        return TableSectionData(row: row)
    }

}
