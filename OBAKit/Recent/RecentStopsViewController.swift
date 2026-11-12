//
//  RecentStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/20/19.
//

import UIKit
import SwiftUI
import Combine
import OBAKitCore

/// Provides an interface to browse recently-viewed information, mostly `Stop`s.
public class RecentStopsViewController: UIViewController, AppContext {

    let application: Application

    let viewModel: RecentStopsViewModel
    private(set) var hostingController: UIHostingController<RecentStopsListView>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init(application: Application) {
        self.application = application
        self.viewModel = RecentStopsViewModel(application: application)

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("recent_stops_controller.title", value: "Recent", comment: "The title of the Recent Stops controller.")
        tabBarItem.image = Icons.recentTabIcon
        tabBarItem.selectedImage = Icons.recentSelectedTabIcon
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: OBALoc("recent_stops.delete_all", value: "Delete All", comment: "A button that deletes all of the recent stops in the app."),
            style: .plain,
            target: self,
            action: #selector(deleteAll)
        )

        view.backgroundColor = ThemeColors.shared.systemBackground

        let listView = RecentStopsListView(
            viewModel: viewModel,
            navigation: makeNavigationHandler()
        )
        let hostingController = UIHostingController(rootView: listView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.pinToSuperview(.edges)
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        updateDeleteAllButtonState()
        bindViewModel()
    }

    private func bindViewModel() {
        viewModel.$recentStops
            .sink { [weak self] stops in
                self?.navigationItem.rightBarButtonItem?.isEnabled = !stops.isEmpty
            }
            .store(in: &cancellables)
    }

    private func updateDeleteAllButtonState() {
        navigationItem.rightBarButtonItem?.isEnabled = !viewModel.recentStops.isEmpty
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        viewModel.loadData()
        updateDeleteAllButtonState()
    }

    // MARK: - Navigation Handler

    func makeNavigationHandler() -> RecentStopsNavigationHandler {
        RecentStopsNavigationHandler(
            selectStop: { [weak self] stop in
                guard let self else { return }
                self.application.viewRouter.navigateTo(stopID: stop.id, from: self)
            },
            selectAlarm: { [weak self] alarmViewModel in
                self?.onSelectAlarm(alarmViewModel)
            },
            deleteAlarm: { [weak self] alarmViewModel in
                self?.onDeleteAlarm(alarmViewModel)
            },
            exploreMap: { [weak self] in
                guard let self else { return }
                self.application.viewRouter.rootNavigateTo(page: .map, from: self)
            },
            makeStopPreview: { [weak self] stopID in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    StopPagePreview(stopID: stopID, application: self.application)
                        .frame(width: 320, height: 400)
                )
            }
        )
    }

    // MARK: - Actions

    @objc func deleteAll() {
        let title = OBALoc("recent_stops.confirmation_alert.title", value: "Are you sure you want to delete all of your recent stops?", comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops.")

        let alertController = UIAlertController.deletionAlert(title: title) { [weak self] _ in
            self?.viewModel.deleteAllRecentStops()
            self?.updateDeleteAllButtonState()
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
            let response = try await apiService.getTripArrivalDepartureAtStop(deepLink: deepLink)

            await MainActor.run {
                self.application.viewRouter.navigateTo(
                    arrivalDeparture: response.entry,
                    from: self,
                    destinationStopID: deepLink.destinationStopID
                )
            }
        } catch {
            await self.application.displayError(error)
        }
    }

    func onDeleteAlarm(_ alarmViewModel: AlarmViewModel) {
        viewModel.delete(alarm: alarmViewModel.alarm)
    }
}
