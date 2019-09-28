//
//  RegionPickerViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/26/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import Eureka
import OBAKitCore

public enum RegionPickerMessage: Int {
    case none, manualSelectionMessage
}

/// Entrypoint for manual management of `Region`s in the app. Includes affordances for creating custom `Region`s.
@objc(OBARegionPickerViewController)
public class RegionPickerViewController: FormViewController, RegionsServiceDelegate {

    // MARK: - Properties

    private let application: Application
    private let message: RegionPickerMessage
    private lazy var doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissRegionPicker))

    // MARK: - Init

    public init(application: Application, message: RegionPickerMessage) {
        self.application = application
        self.message = message

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("region_picker_controller.title", value: "Select a Region", comment: "Region Picker view controller title")

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
        let section: Section

        switch message {
        case .manualSelectionMessage:
            section = Section(
                footer: NSLocalizedString("region_picker.manual_selection_message",
                                          value: "We can't automatically select a region for you. Please choose a region below and then tap on the Done button.",
                                          comment: "Explanation for why the user is seeing this screen."))
        case .none:
            section = Section()
        }

        var skipFirst = false

        section <<< SwitchRow(autoSelectTag) {
            $0.tag = autoSelectTag
            $0.title = NSLocalizedString("region_picker_controller.automatically_select_region_switch_title", value: "Automatically select region", comment: "Title next to the switch that toggles whether the user can manually pick their region.")
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
        let title = NSLocalizedString("region_picker.region_section.title", value: "Regions", comment: "Title of the Regions section.")
        let section = SelectableSection<ListCheckRow<String>>(title, selectionType: .singleSelection(enableDeselection: false)) {
            $0.onSelectSelectableRow = { [weak self] _, row in
                guard
                    let self = self,
                    row.selectableValue != nil
                else { return }

                self.doneButton.isEnabled = true
            }
        }

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
                $0.tag = selectedRegionTag
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
        // This is sort of a hacky test for determining whether we
        // should be reloading the root interface or simply dismissing
        // this controller, but it's good enough for now. Nice thing to
        // revisit later though.
        if message == .manualSelectionMessage {
            application.reloadRootUserInterface()
        }
        else {
            dismiss(animated: true, completion: nil)
        }
    }
}
