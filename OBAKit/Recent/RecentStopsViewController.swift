//
//  RecentStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/20/19.
//

import UIKit
import Combine
import OBAKitCore

/// Provides an interface to browse recently-viewed information, mostly `Stop`s.
public class RecentStopsViewController: UIViewController,
    AppContext,
    OBAListViewDataSource,
    OBAListViewContextMenuDelegate {

    let application: Application

    private let viewModel: RecentStopsViewModel
    private let listView = OBAListView()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(application: Application) {
        self.application = application
        self.viewModel = RecentStopsViewModel(application: application)

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

        bindViewModel()
    }

    private func bindViewModel() {
        // `@Published` fires from `willSet`, so a synchronous sink would read the *old*
        // stored values via `items(for:)` (alarms / recentStops). The main-queue hop
        // defers the closure until after the property writes complete.
        Publishers.CombineLatest(viewModel.$alarms, viewModel.$recentStops)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.listView.applyData(animated: true) }
            .store(in: &cancellables)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewModel.loadData()
    }

    // MARK: - Actions

    @objc func deleteAll() {
        let title = OBALoc("recent_stops.confirmation_alert.title", value: "Are you sure you want to delete all of your recent stops?", comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops.")

        let alertController = UIAlertController.deletionAlert(title: title) { [weak self] _ in
            self?.viewModel.deleteAllRecentStops()
        }

        present(alertController, animated: true, completion: nil)
    }

    func onSelectAlarm(_ viewModel: AlarmViewModel) {
        Task(priority: .userInitiated) {
            await self.showDeepLink(deepLink: viewModel.deepLink)
        }
    }

    func showDeepLink(deepLink: ArrivalDepartureDeepLink) async {
        guard let apiService = self.application.apiService else { return }
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
            await self.application.displayError(error)
        }
    }

    func onDeleteAlarm(_ alarmViewModel: AlarmViewModel) {
        viewModel.delete(alarm: alarmViewModel.alarm)
    }

    // MARK: - Sections

    private var alarmSection: OBAListViewSection? {
        let alarms = viewModel.alarms
        guard alarms.count > 0 else { return nil }

        let rows = alarms.compactMap { alarm in
            return AlarmViewModel(withAlarm: alarm, onSelect: onSelectAlarm, onDelete: onDeleteAlarm)
        }

        let title = OBALoc("recent_stops_controller.alarms_section.title", value: "Alarms", comment: "Title of the Alarms section of the Recents controller")
        return OBAListViewSection(id: "alarms", title: title, contents: rows)
    }

    private var stopsSection: OBAListViewSection? {
        let stops = viewModel.recentStops
        guard stops.count > 0 else { return nil }

        let rows = stops.map { stop -> StopRowItem in
            let onSelect: OBAListViewAction<StopRowItem> = { [unowned self] viewModel in
                self.application.viewRouter.navigateTo(stopID: viewModel.stopID, from: self)
            }

            let onDelete: OBAListViewAction<StopRowItem> = { [unowned self] _ in
                self.viewModel.delete(recentStop: stop)
            }

            return StopRowItem(withStop: stop, onSelect: onSelect, onDelete: onDelete)
        }

        let title = viewModel.alarms.count > 0 ? Strings.recentStops : nil
        return OBAListViewSection(id: "recent_stops", title: title, contents: rows)
    }

    // MARK: - OBAListView

    public func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [alarmSection, stopsSection].compactMap { $0 }
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
        guard let stopViewModel = item.as(StopRowItem.self) else { return nil }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { [unowned self] () -> UIViewController? in
            let stopVC = self.application.viewRouter.makeStopController(stopID: stopViewModel.stopID)
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
