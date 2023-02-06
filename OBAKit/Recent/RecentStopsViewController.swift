//
//  RecentStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/20/19.
//

import UIKit
import OBAKitCore

/// Provides an interface to browse recently-viewed information, mostly `Stop`s.
public class RecentStopsViewController: UIViewController,
    AppContext,
    OBAListViewDataSource,
    OBAListViewContextMenuDelegate {

    let application: Application

    let listView = OBAListView()

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("recent_stops_controller.title", value: "Recent", comment: "The title of the Recent Stops controller.")
        tabBarItem.image = Icons.recentTabIcon
        tabBarItem.selectedImage = Icons.recentSelectedTabIcon

        listView.obaDataSource = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: OBALoc("recent_stops.delete_all", value: "Delete All", comment: "A button that deletes all of the recent stops in the app."), style: .plain, target: self, action: #selector(deleteAll))

        view.backgroundColor = ThemeColors.shared.systemBackground
        view.addSubview(listView)
        listView.contextMenuDelegate = self
        listView.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        application.userDataStore.deleteExpiredAlarms()
        listView.applyData()
    }

    // MARK: - Actions

    @objc func deleteAll() {
        let title = OBALoc("recent_stops.confirmation_alert.title", value: "Are you sure you want to delete all of your recent stops?", comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops.")

        let alertController = UIAlertController.deletionAlert(title: title) { [weak self] _ in
            guard let self = self else { return }
            self.application.userDataStore.deleteAllRecentStops()
            self.listView.applyData(animated: true)
        }

        present(alertController, animated: true, completion: nil)
    }

    func onSelectAlarm(_ viewModel: AlarmViewModel) {
        Task(priority: .userInitiated) {
            await self.showDeepLink(deepLink: viewModel.deepLink)
        }
    }

    func showDeepLink(deepLink: ArrivalDepartureDeepLink) async {
        guard let apiService = self.application.betterAPIService else { return }
        await MainActor.run {
            ProgressHUD.show()
        }

        defer {
            Task { @MainActor in
                ProgressHUD.dismiss()
            }
        }

        do {
            let response = try await apiService.getTripArrivalDepartureAtStop(
                stopID: deepLink.stopID,
                tripID: deepLink.tripID,
                serviceDate: deepLink.serviceDate,
                vehicleID: deepLink.vehicleID,
                stopSequence: deepLink.stopSequence)

            await MainActor.run {
                self.application.viewRouter.navigateTo(arrivalDeparture: response.entry, from: self)
            }
        } catch {
            self.application.displayError(error)
        }
    }

    func onDeleteAlarm(_ viewModel: AlarmViewModel) {
        Task {
            try? await self.application.obacoService?.deleteAlarm(url: viewModel.alarm.url)
        }
        self.application.userDataStore.delete(alarm: viewModel.alarm)
        self.listView.applyData(animated: true)
    }

    // MARK: - Sections

    private var alarms: OBAListViewSection? {
        let alarms = application.userDataStore.alarms
        guard alarms.count > 0 else {
            return nil
        }

        let rows = alarms.compactMap { alarm in
            return AlarmViewModel(withAlarm: alarm, onSelect: onSelectAlarm, onDelete: onDeleteAlarm)
        }

        let title = OBALoc("recent_stops_controller.alarms_section.title", value: "Alarms", comment: "Title of the Alarms section of the Recents controller")
        return OBAListViewSection(id: "alarms", title: title, contents: rows)
    }

    private var stops: OBAListViewSection? {
        guard let currentRegion = application.currentRegion else {
            return nil
        }

        let stops = application.userDataStore.recentStops.filter { $0.regionIdentifier == currentRegion.regionIdentifier }
        guard stops.count > 0 else {
            return nil
        }

        let rows = stops.map { stop -> StopViewModel in
            let onSelect: OBAListViewAction<StopViewModel> = { [unowned self] viewModel in
                self.application.viewRouter.navigateTo(stopID: viewModel.stopID, from: self)
            }

            let onDelete: OBAListViewAction<StopViewModel> = { [unowned self] _ in
                self.application.userDataStore.delete(recentStop: stop)
                self.listView.applyData(animated: true)
            }

            return StopViewModel(withStop: stop, onSelect: onSelect, onDelete: onDelete)
        }

        let title = application.userDataStore.alarms.count > 0 ? Strings.recentStops : nil
        return OBAListViewSection(id: "recent_stops", title: title, contents: rows)
    }

    // MARK: - OBAListView

    public func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [alarms, stops].compactMap { $0 }
    }

    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        let title = OBALoc("recent_stops.empty_set.title", value: "No Recent Stops", comment: "Title for the empty set indicator on the Recent Stops controller.")
        let subtitle = OBALoc("recent_stops.empty_set.body", value: "Transit stops that you view in the app will appear here.", comment: "Body for the empty set indicator on the Recent Stops controller.")
        let buttonText = OBALoc("recent_stops.empty_set.button", value: "Find Stops on Maps", comment: "The button title for taking the user to the map view to find stops.")
        let button = ActivityIndicatedButton.Configuration(
            text: buttonText,
            largeContentImage: Icons.mapTabIcon,
            showsActivityIndicatorOnTap: false) {
            self.application.viewRouter.rootNavigateTo(page: .map)
        }

        return .standard(.init(title: title, body: subtitle, buttonConfig: button))
    }

    fileprivate var currentPreviewingViewController: UIViewController?
    public func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        guard let stopViewModel = item.as(StopViewModel.self) else { return nil }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { [unowned self] () -> UIViewController? in
            let stopVC = StopViewController(application: self.application, stopID: stopViewModel.stopID)
            self.currentPreviewingViewController = stopVC
            return stopVC
        }

        let commitPreviewAction: VoidBlock = { [unowned self] in
            guard let vc = self.currentPreviewingViewController else { return }
            (vc as? Previewable)?.exitPreviewMode()
            self.application.viewRouter.navigate(to: vc, from: self)
        }

        return OBAListViewMenuActions(previewProvider: previewProvider, performPreviewAction: commitPreviewAction, contextMenuProvider: nil)
    }
}
