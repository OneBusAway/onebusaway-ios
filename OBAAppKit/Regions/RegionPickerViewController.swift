//
//  RegionPickerViewController.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/26/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBAKit

@objc(OBARegionPickerViewController)
public class RegionPickerViewController: UIViewController {
    let application: Application
    var regions = [Region]()

    var selectedRegion: Region? {
        didSet {
            navigationItem.rightBarButtonItem?.isEnabled = selectedRegion != nil
        }
    }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero)
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]


        return table
    }()

    init(application: Application) {
        self.application = application
        self.regions = self.application.regionsService.regions

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("region_picker_controller.title", value: "Select a Region", comment: "Region Picker view controller title")

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(updateRegionSelection))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: RegionPickerViewController.cellIdentifier)
        tableView.dataSource = self
        tableView.delegate = self

        tableView.frame = view.bounds
        view.addSubview(tableView)
    }

    @objc func updateRegionSelection() {
        guard let selectedRegion = selectedRegion else {
            return
        }

        application.regionsService.currentRegion = selectedRegion
        application.reloadRootUserInterface()
    }
}

extension RegionPickerViewController: UITableViewDataSource, UITableViewDelegate {
    private static let cellIdentifier = "CellIdentifier"

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return application.regionsService.regions.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RegionPickerViewController.cellIdentifier, for: indexPath)
        let region = regions[indexPath.row]

        cell.textLabel?.text = region.regionName

        if region == selectedRegion {
            cell.accessoryType = .checkmark
        }
        else {
            cell.accessoryType = .none
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let region = regions[indexPath.row]
        selectedRegion = region

        tableView.reloadData()
    }
}
