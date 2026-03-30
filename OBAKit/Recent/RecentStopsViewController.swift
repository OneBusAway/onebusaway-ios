//
//  RecentStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/20/19.
//

import UIKit
import SwiftUI
import OBAKitCore

/// Provides an interface to browse recently-viewed information, mostly `Stop`s.
public class RecentStopsViewController: UIViewController, AppContext {

    public let application: Application

    private let viewModel: RecentStopsViewModel
    private var hostingController: UIHostingController<RecentStopsView>!

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
            action: #selector(confirmDeleteAll)
        )

        // Build SwiftUI view and embed it
        var swiftUIView = RecentStopsView(viewModel: viewModel)
        swiftUIView.hostViewController = self
        swiftUIView.application = application

        hostingController = UIHostingController(rootView: swiftUIView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.reload()
    }

    // MARK: - Delete All

    @objc private func confirmDeleteAll() {
        let title = OBALoc(
            "recent_stops.confirmation_alert.title",
            value: "Are you sure you want to delete all of your recent stops?",
            comment: "Title for a confirmation alert displayed before the user deletes all of their recent stops."
        )
        let alert = UIAlertController.deletionAlert(title: title) { [weak self] _ in
            self?.viewModel.deleteAllStops()
        }
        present(alert, animated: true)
    }
}
