//
//  RegionPickerViewController.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/26/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBANetworkingKit
import OBALocationKit

@objc(OBARegionPickerViewController)
class RegionPickerViewController: UIViewController {
    let application: Application
    var regions = [Region]()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero)
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self

        return table
    }()

    init(application: Application) {
        self.application = application
        self.regions = self.application.regionsService.regions

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("region_picker_controller.title", value: "Select a Region", comment: "Region Picker view controller title")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: RegionPickerViewController.cellIdentifier)

        tableView.frame = view.bounds
        view.addSubview(tableView)
    }
}

extension RegionPickerViewController: UITableViewDataSource, UITableViewDelegate {
    private static let cellIdentifier = "CellIdentifier"

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return application.regionsService.regions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RegionPickerViewController.cellIdentifier, for: indexPath)
        let region = regions[indexPath.row]

        cell.textLabel?.text = region.regionName

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let region = regions[indexPath.row]

        application.regionsService.currentRegion = region
    }
}
