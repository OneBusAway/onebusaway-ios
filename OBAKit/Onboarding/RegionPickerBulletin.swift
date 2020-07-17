//
//  RegionPickerBulletin.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore
import BLTNBoard

class RegionPickerItem: BLTNPageItem {
    private let regionPicker: RegionPicker
    private let regionsService: RegionsService

    init(regionsService: RegionsService) {
        self.regionsService = regionsService
        self.regionPicker = RegionPicker(regionsService: regionsService)

        super.init(title: OBALoc("region_picker.title", value: "Choose Region", comment: "Title of the Region Picker Item, which lets the user choose a new region from the map."))

        descriptionText = OBALoc("region_picker.description_text", value: "Choose your transit region to use the app.", comment: "Descriptive text for the region picker card.")
        isDismissable = regionsService.currentRegion != nil
        actionButtonTitle = Strings.ok

        actionHandler = { [weak self] _ in
            guard
                let self = self,
                let region = self.regionPicker.selectedRegion
            else { return }

            self.regionsService.currentRegion = region

            // When selecting a region from the RegionPickerBulletin, ensure that automaticallySelectRegion is false.
            // Since the user is manually selecting a Region, it doesn't make sense to leave control with the app on
            // this decision any longer.
            self.regionsService.automaticallySelectRegion = false

            self.manager?.dismissBulletin()
        }
    }

    override func makeViewsUnderDescription(with interfaceBuilder: BLTNInterfaceBuilder) -> [UIView]? {
        regionPicker.prepareForDisplay()
        return [regionPicker.pickerView]
    }
}

fileprivate class RegionPicker: NSObject, UIPickerViewDataSource, UIPickerViewDelegate, RegionsServiceDelegate {

    init(regionsService: RegionsService) {
        self.regionsService = regionsService

        super.init()

        pickerItems = self.regionsService.regions

        self.regionsService.addDelegate(self)
    }

    deinit {
        regionsService.removeDelegate(self)
    }

    var selectedRegion: Region? {
        pickerItems[pickerView.selectedRow(inComponent: 0)]
    }

    // MARK: - Regions Service

    private let regionsService: RegionsService

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        pickerItems = regions
        pickerView.reloadAllComponents()
    }

    // MARK: - Picker View

    private var pickerItems = [Region]()

    lazy var pickerView: UIPickerView = {
        let picker = UIPickerView(frame: .zero)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.delegate = self
        picker.dataSource = self
        return picker
    }()

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        pickerItems.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        pickerItems[row].name
    }

    /// Configures the picker view's default value
    func prepareForDisplay() {
        if let currentRegion = regionsService.currentRegion, let index = pickerItems.firstIndex(of: currentRegion) {
            pickerView.selectRow(index, inComponent: 0, animated: false)
        }
    }
}
