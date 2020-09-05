//
//  RegionPickerViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Eureka
import OBAKitCore

/// Entrypoint for manual management of `Region`s in the app. Includes affordances for creating custom `Region`s.
class RegionPickerViewController: FormViewController, RegionsServiceDelegate {

    // MARK: - Properties

    private let application: Application
    private lazy var doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissRegionPicker))

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("region_picker_controller.title", value: "Select a Region", comment: "Region Picker view controller title")

        doneButton.isEnabled = (application.regionsService.currentRegion != nil)
        navigationItem.rightBarButtonItem = doneButton
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override public func viewDidLoad() {
        super.viewDidLoad()
        form
            +++ autoSelectSwitchSection
            +++ selectedRegionSection

        setFormValues()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if
            !application.regionsService.automaticallySelectRegion,
            let selectedRow = selectedRegionSection.selectedRow(),
            let stringValue = selectedRow.selectableValue,
            let regionID = Int(stringValue),
            let region = application.regionsService.find(id: regionID)
        {
            application.regionsService.currentRegion = region
        }
    }

    // MARK: - Load Form

    private func setFormValues() {
        var values = [String: Any]()
        values[autoSelectTag] = application.regionsService.automaticallySelectRegion
        form.setValues(values)
    }

    // MARK: - Auto-Select Switch

    private lazy var autoSelectSwitchSection: Section = {
        let section = Section()
        var skipFirst = false

        section <<< SwitchRow(autoSelectTag) {
            $0.tag = autoSelectTag
            $0.title = OBALoc("region_picker_controller.automatically_select_region_switch_title", value: "Automatically select region", comment: "Title next to the switch that toggles whether the user can manually pick their region.")
            $0.onChange { [weak self] (row) in
                guard
                    skipFirst,
                    let self = self,
                    let value = row.value
                else {
                    skipFirst = true
                    return
                }

                self.application.regionsService.automaticallySelectRegion = value
            }
        }

        return section
    }()

    // MARK: - Region List Section

    private lazy var selectedRegionSection: SelectableSection<ListCheckRow<String>> = {
        let title = OBALoc("region_picker.region_section.title", value: "Regions", comment: "Title of the Regions section.")
        let section = SelectableSection<ListCheckRow<String>>(title, selectionType: .singleSelection(enableDeselection: false))

        let selectedRegionID: String?
        if let region = application.regionsService.currentRegion {
            selectedRegionID = String(region.regionIdentifier)
        }
        else {
            selectedRegionID = nil
        }

        for region in sortedRegions {
            let regionID = String(region.regionIdentifier)
            section <<< ListCheckRow<String>(regionID) {
                $0.title = region.name
                $0.selectableValue = regionID
                $0.value = selectedRegionID == regionID ? regionID : nil
                $0.disabled = "$autoSelectTag == true"
            }
        }

        return section
    }()

    /// Sorts the `regions` list by selection and then alphabetically.
    private var sortedRegions: [Region] {
        let currentRegionID = application.currentRegion?.regionIdentifier

        let regions = application.regionsService.regions.sorted { (r1, r2) -> Bool in
            if r1.regionIdentifier == currentRegionID {
                return true
            }
            else if r2.regionIdentifier == currentRegionID {
                return false
            }
            else {
                return r2.name > r1.name
            }
        }

        return regions
    }

    private let selectedRegionTag = "selectedRegionTag"
    private let autoSelectTag = "autoSelectTag"

    // MARK: - Actions

    @objc private func dismissRegionPicker() {
        dismiss(animated: true, completion: nil)
    }
}
