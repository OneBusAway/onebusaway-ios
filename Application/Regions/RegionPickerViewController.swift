//
//  RegionPickerViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/26/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import AloeStackView
/// Displayed when the user's region cannot be automatically determined by location services, such as when the user has denied the app access to their location.
@objc(OBARegionPickerViewController)
public class RegionPickerViewController: UIViewController, AloeStackTableBuilder {
    let application: Application
    var theme: Theme { application.theme }

    var regions = [Region]()

    var selectedRegion: Region? {
        didSet {
            navigationItem.rightBarButtonItem?.isEnabled = selectedRegion != nil
        }
    }

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: application.theme.colors.systemBackground
    )

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

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        loadData()
    }

    @objc func updateRegionSelection() {
        guard let selectedRegion = selectedRegion else {
            return
        }

        application.regionsService.currentRegion = selectedRegion
        application.reloadRootUserInterface()
    }

    // MARK: - Data Loading

    private func loadData() {
        let selectedRegionIdentifier = selectedRegion?.regionIdentifier ?? -1

        // add auto select switch

        for region in regions {
            var accessory: UITableViewCell.AccessoryType = .none

            if region.regionIdentifier == selectedRegionIdentifier {
                accessory = .checkmark
            }

            let row = DefaultTableRowView(title: region.regionName, accessoryType: accessory)
            addGroupedTableRowToStack(row) { [weak self] _ in
                guard let self = self else { return }

                self.selectedRow = row
                self.selectedRegion = region
            }
        }
    }

    private var selectedRow: DefaultTableRowView? {
        didSet {
            if let oldValue = oldValue {
                oldValue.accessoryType = .none
            }
            selectedRow?.accessoryType = .checkmark
        }
    }
}
