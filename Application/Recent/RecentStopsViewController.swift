//
//  RecentStopsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/20/19.
//

import UIKit

/// Provides an interface to browse recently-viewed information, mostly `Stop`s.
@objc(OBARecentStopsViewController) public class RecentStopsViewController: UIViewController {

    let application: Application

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("recent_stops_controller.title", value: "Recent Stops", comment: "The title of the Recent Stops controller.")
        tabBarItem.image = Icons.recentTabIcon
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let tableView = UITableView(frame: .zero)

    public override func viewDidLoad() {
        super.viewDidLoad()

        tableView.frame = view.bounds
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "identifier")
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        tableView.reloadData()
    }
}

extension RecentStopsViewController: UITableViewDelegate, UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return application.userDataStore.recentStops.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "identifier", for: indexPath)
        let stop = application.userDataStore.recentStops[indexPath.row]

        cell.textLabel!.text = stop.name

        return cell
    }
}
