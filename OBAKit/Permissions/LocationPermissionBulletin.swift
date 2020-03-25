//
//  LocationPermissionBulletin.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/21/19.
//

import Foundation
import BLTNBoard
import OBAKitCore

/// Displays a modal card UI that prompts the user for access to their location.
///
/// This class is responsible for the initial location permission prompt that gets
/// displayed when the user first launches the application.
class LocationPermissionBulletin: NSObject {
    private lazy var bulletinManager = BLTNItemManager(rootItem: introPage)

    private lazy var introPage: LocationPermissionItem = {
        let introPage = LocationPermissionItem()

        introPage.actionHandler = { [weak self] _ in
            self?.bulletinManager.dismissBulletin()
            self?.locationService.requestInUseAuthorization()
        }

        introPage.alternativeHandler = { [weak self] _ in
            guard let self = self else { return }
            self.locationService.canPromptUserForPermission = false
            self.bulletinManager.push(item: self.regionPickerItem)
        }
        return introPage
    }()

    private lazy var regionPickerItem: RegionPickerItem = {
        let picker = RegionPickerItem(regionsService: regionsService)
        return picker
    }()

    private let locationService: LocationService
    private let regionsService: RegionsService

    init(locationService: LocationService, regionsService: RegionsService) {
        self.locationService = locationService
        self.regionsService = regionsService

        super.init()
    }

    func show(in application: UIApplication) {
        bulletinManager.showBulletin(in: application)
    }
}

// MARK: - LocationPermissionItem

class LocationPermissionItem: BLTNPageItem {
    override init() {
        super.init(title: OBALoc("location_permission_bulletin.title", value: "Welcome!", comment: "Title of the alert that appears to request your location."))

        isDismissable = false

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.brand)
        image = squircleRenderer.drawImageOnRoundedRect(Icons.nearMe)

        descriptionText = OBALoc("location_permission_bulletin.description_text", value: "Please allow the app to access your location to make it easier to find your transit stops.", comment: "Description of why we need location services")

        actionButtonTitle = OBALoc("location_permission_bulletin.buttons.give_permission", value: "Allow Access", comment: "This button signals the user is willing to grant location access to the app.")

        alternativeButtonTitle = OBALoc("location_permission_bulletin.buttons.deny_permission", value: "Maybe Later", comment: "This button rejects the application's request to see the user's location.")
    }
}

// MARK: - RegionPickerItem

class RegionPickerBulletin: NSObject {
    private lazy var bulletinManager = BLTNItemManager(rootItem: regionPickerItem)

    private lazy var regionPickerItem: RegionPickerItem = {
        let picker = RegionPickerItem(regionsService: regionsService)
        return picker
    }()

    public let regionsService: RegionsService

    init(regionsService: RegionsService) {
        self.regionsService = regionsService

        super.init()
    }

    func show(in application: UIApplication) {
        guard !bulletinManager.isShowingBulletin else { return }            // Fixes #185.
        bulletinManager.showBulletin(in: application)
    }
}

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
