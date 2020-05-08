//
//  AlarmBuilderViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/4/19.
//

import UIKit
import BLTNBoard
import OBAKitCore

public enum AlarmBuilderErrors: Error {
    case creationFailed
}

protocol AlarmBuilderDelegate: NSObjectProtocol {

    /// Delegate method that gets called when the `AlarmBuilder` begins its request to create an `Alarm`.
    /// A perfect opportunity to display a loading indicator.
    /// - Parameter alarmBuilder: The `AlarmBuilder` object.
    func alarmBuilderStartedRequest(_ alarmBuilder: AlarmBuilder)

    /// Delegate method that gets called when the `AlarmBuilder` has successfully created an `Alarm`.
    /// - Parameter alarmBuilder: The `AlarmBuilder` object.
    /// - Parameter alarm: The created `Alarm`.
    func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm)

    /// Delegate method that gets called when the `AlarmBuilder` experiences an error while creating an `Alarm`.
    /// - Parameter alarmBuilder: The `AlarmBuilder` object.
    /// - Parameter error: The `Error` preventing the creation of an `Alarm`.
    func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error)
}

/// Manages the creation of `Alarm` objects. Uses the `BLTNBoard` framework to drive its UI.
class AlarmBuilder: NSObject {
    private let arrivalDeparture: ArrivalDeparture
    private let application: Application

    // MARK: - Delegate

    public weak var delegate: AlarmBuilderDelegate?

    // MARK: - BLTNBoard Components

    public lazy var bulletinManager: BLTNItemManager = {
        let manager = BLTNItemManager(rootItem: timePickerPage)
        manager.edgeSpacing = .compact
        return manager
    }()

    private let timePickerPage: AlarmTimePickerItem

    // MARK: - Init

    init(arrivalDeparture: ArrivalDeparture, application: Application, delegate: AlarmBuilderDelegate?) {
        self.arrivalDeparture = arrivalDeparture
        self.application = application
        self.delegate = delegate
        self.timePickerPage = AlarmTimePickerItem(arrivalDeparture: arrivalDeparture)

        super.init()

        self.timePickerPage.actionHandler = { [weak self] item in
            guard
                let self = self,
                let item = item as? AlarmTimePickerItem
            else { return }

            let minutes = item.timePickerManager.selectedMinutes
            self.createAlarm(minutes: minutes)
        }
    }

    deinit {
        alarmOperation?.cancel()
    }

    // MARK: - Public Methods

    public func showBulletin(above viewController: UIViewController) {
        bulletinManager.showBulletin(above: viewController)
    }

    // MARK: - Alarm Creation

    private var alarmOperation: DecodableOperation<Alarm>?

    private func createAlarm(minutes: Int) {
        guard
            let modelService = application.obacoService,
            let pushService = application.pushService,
            let currentRegion = application.currentRegion
        else { return }

        let arrivalDeparture = self.arrivalDeparture

        SVProgressHUD.show()

        pushService.requestPushID { [weak self] userPushID in
            guard let self = self else { return }

            let op = modelService.postAlarm(minutesBefore: minutes, arrivalDeparture: arrivalDeparture, userPushID: userPushID)
            op.complete { [weak self] result in
                SVProgressHUD.dismiss()
                guard let self = self else { return }

                switch result {
                case .failure:
                    self.delegate?.alarmBuilder(self, error: AlarmBuilderErrors.creationFailed)
                case .success(let response):
                    let alarm = response
                    alarm.deepLink = ArrivalDepartureDeepLink(arrivalDeparture: self.arrivalDeparture, regionID: currentRegion.regionIdentifier)
                    alarm.set(tripDate: self.arrivalDeparture.arrivalDepartureDate, alarmOffset: minutes)
                    self.delegate?.alarmBuilder(self, alarmCreated: alarm)
                }

                self.bulletinManager.dismissBulletin(animated: true)
            }

            self.alarmOperation = op
        }
    }
}

// MARK: - AlarmTimePickerItem

/// The BLTNBoard page item that displays the alarm time picker
class AlarmTimePickerItem: BLTNPageItem {
    private let arrivalDeparture: ArrivalDeparture
    let timePickerManager: AlarmTimePickerManager

    init(arrivalDeparture: ArrivalDeparture) {
        self.arrivalDeparture = arrivalDeparture
        self.timePickerManager = AlarmTimePickerManager(arrivalDeparture: arrivalDeparture)

        super.init()

        descriptionText = OBALoc("alarm_time_picker.description", value: "Remind me when this vehicle will depart in:", comment: "Explains what the Alarm Time Picker page does.")
        isDismissable = true
        actionButtonTitle = Strings.addAlarm
    }

    override func makeViewsUnderDescription(with interfaceBuilder: BLTNInterfaceBuilder) -> [UIView]? {
        timePickerManager.prepareForDisplay()
        return [timePickerManager.pickerView]
    }
}

// MARK: - AlarmTimePickerManager

/// Wraps a `UIPickerView` with logic necessary to create a list of possible alarm time values
/// for the provided `ArrivalDeparture`.
class AlarmTimePickerManager: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {

    private let pickerItems: [Int]

    private let arrivalDeparture: ArrivalDeparture

    lazy var pickerView: UIPickerView = {
        let picker = UIPickerView(frame: .zero)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.delegate = self
        picker.dataSource = self
        return picker
    }()

    init(arrivalDeparture: ArrivalDeparture) {
        self.arrivalDeparture = arrivalDeparture
        self.pickerItems = AlarmTimePickerManager.incrementsForDeparture(arrivalDeparture.arrivalDepartureMinutes)
    }

    /// Configures the picker view's default value
    func prepareForDisplay() {
        let row = pickerItems.firstIndex(of: 10) ?? 0
        pickerView.selectRow(row, inComponent: 0, animated: false)
    }

    var selectedMinutes: Int {
        pickerItems[pickerView.selectedRow(inComponent: 0)]
    }

    /// Creates an array of `Int`s representing the countdown of minutes that will be displayed in this controller's picker.
    /// - Parameter minutes: Total minutes until departure.
    private class func incrementsForDeparture(_ minutes: Int) -> [Int] {
        var increments = [Int]()

        var cursor = 1

        while cursor < minutes {
            increments.append(cursor)

            if cursor < 10 {
                cursor += 1
            }
            else if cursor < 30 {
                cursor += 5
            }
            else if cursor < 120 {
                cursor += 15
            }
            else {
                cursor += 30
            }
        }

        return increments.reversed()
    }

    // MARK: - Picker Data Source

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { pickerItems.count }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let minutes = pickerItems[row]
        if minutes == 1 {
            return OBALoc("alarm_builder_controller.one_minute", value: "1 minute", comment: "One minute/1 minute")
        }
        else {
            let fmt = OBALoc("alarm_builder_controller.minutes_fmt", value: "%d minutes", comment: "{X} minutes. always plural.")
            return String(format: fmt, minutes)
        }
    }
}
