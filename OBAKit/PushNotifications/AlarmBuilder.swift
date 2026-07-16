//
//  AlarmBuilder.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import BLTNBoard
import OBAKitCore

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

    /// Whether the "Track on Lock Screen" toggle was on when the user tapped Add Alarm.
    var trackOnLockScreen: Bool { timePickerPage.trackOnLockScreen }

    // MARK: - Init

    /// - Parameter initialMinutes: Pre-selects this lead time in the picker.
    ///   Pass the current alarm's lead time when re-presenting the bulletin to
    ///   change an existing alarm; `nil` falls back to the user's default alarm
    ///   lead time preference.
    init(arrivalDeparture: ArrivalDeparture, application: Application, initialMinutes: Int? = nil, delegate: AlarmBuilderDelegate?) {
        self.arrivalDeparture = arrivalDeparture
        self.application = application
        self.delegate = delegate
        self.timePickerPage = AlarmTimePickerItem(
            arrivalDeparture: arrivalDeparture,
            initialMinutes: initialMinutes ?? application.userDataStore.defaultAlarmLeadTimeMinutes,
            userDefaults: application.userDefaults
        )

        super.init()

        self.timePickerPage.actionHandler = { [weak self] item in
            guard
                let self = self,
                let item = item as? AlarmTimePickerItem,
                // No selectable lead time: the departure slipped inside a minute
                // between the row rendering its alarm affordance and the user
                // confirming the bulletin. Nothing to arm, so just close.
                let minutes = item.timePickerManager.selectedMinutes
            else {
                self?.bulletinManager.dismissBulletin(animated: true)
                return
            }

            Task {
                await self.createAlarm(minutes: minutes)
            }
        }
    }

    // MARK: - Public Methods

    public func showBulletin(above viewController: UIViewController) {
        guard !bulletinManager.isShowingBulletin else {
            return
        }

        bulletinManager.showBulletin(above: viewController)
    }

    // MARK: - Alarm Creation
    private func createAlarm(minutes: Int) async {
        guard
            let modelService = application.obacoService,
            let pushService = application.pushService,
            let currentRegion = application.currentRegion
        else { return }

        let arrivalDeparture = self.arrivalDeparture

        ProgressHUD.show()

        defer {
            Task { @MainActor in
                ProgressHUD.dismiss()
                self.bulletinManager.dismissBulletin(animated: true)
            }
        }

        let userPushID = await pushService.pushID()
        let alarm: Alarm
        do {
            alarm = try await modelService.postAlarm(minutesBefore: minutes, arrivalDeparture: arrivalDeparture, userPushID: userPushID)
        } catch {
            self.delegate?.alarmBuilder(self, error: AlarmBuilderErrors.creationFailed)
            return
        }

        alarm.deepLink = ArrivalDepartureDeepLink(arrivalDeparture: self.arrivalDeparture, regionID: currentRegion.regionIdentifier)
        alarm.set(tripDate: self.arrivalDeparture.arrivalDepartureDate, alarmOffset: minutes)

        if let delegate {
            await MainActor.run {
                delegate.alarmBuilder(self, alarmCreated: alarm)
            }
        }
    }

    public enum AlarmBuilderErrors: Error {
        case creationFailed
    }
}

// MARK: - AlarmTimePickerItem

/// The BLTNBoard page item that displays the alarm time picker
class AlarmTimePickerItem: ThemedBulletinPage {
    private let arrivalDeparture: ArrivalDeparture
    let timePickerManager: AlarmTimePickerManager
    private let userDefaults: UserDefaults
    private weak var trackSwitch: UISwitch?

    private static let trackOnLockScreenKey = "AlarmTimePickerItem.trackOnLockScreen"

    /// The current value of the "Track on Lock Screen" toggle.
    var trackOnLockScreen: Bool { userDefaults.bool(forKey: Self.trackOnLockScreenKey) }

    // Required by ThemedBulletinPage's initializer contract (see its init(title:)).
    @available(*, unavailable)
    nonisolated override init(title: String) {
        fatalError("Use init(arrivalDeparture:initialMinutes:userDefaults:)")
    }

    init(arrivalDeparture: ArrivalDeparture, initialMinutes: Int, userDefaults: UserDefaults) {
        self.arrivalDeparture = arrivalDeparture
        self.userDefaults = userDefaults
        self.timePickerManager = AlarmTimePickerManager(arrivalDeparture: arrivalDeparture, initialMinutes: initialMinutes)

        let title = OBALoc("alarm_time_picker.title", value: "Add Reminder", comment: "Title of the Alarm Time Picker page.")
        super.init(title: title)

        userDefaults.register(defaults: [Self.trackOnLockScreenKey: true])

        descriptionText = OBALoc("alarm_time_picker.description", value: "Remind me when this vehicle will depart in:", comment: "Explains what the Alarm Time Picker page does.")
        isDismissable = true
        actionButtonTitle = Strings.addAlarm
    }

    // nonisolated to match BLTNPageItem's nonisolated declaration; BLTNBoard only
    // calls this while presenting UI on the main thread.
    nonisolated override func makeViewsUnderDescription(with interfaceBuilder: BLTNInterfaceBuilder) -> [UIView]? {
        MainActor.assumeIsolated {
            timePickerManager.prepareForDisplay()
            return [timePickerManager.pickerView, makeTrackOnLockScreenRow()]
        }
    }

    private func makeTrackOnLockScreenRow() -> UIView {
        let label = UILabel()
        label.text = OBALoc(
            "alarm_time_picker.track_on_lock_screen",
            value: "Track on Lock Screen",
            comment: "Toggle label that starts a Live Activity widget on the Lock Screen when an alarm is set."
        )
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        let toggle = UISwitch()
        toggle.isOn = trackOnLockScreen
        toggle.addTarget(self, action: #selector(trackSwitchChanged(_:)), for: .valueChanged)
        trackSwitch = toggle

        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16

        let container = UIView()
        container.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    @objc private func trackSwitchChanged(_ sender: UISwitch) {
        userDefaults.set(sender.isOn, forKey: Self.trackOnLockScreenKey)
    }
}

// MARK: - AlarmTimePickerManager

/// Wraps a `UIPickerView` with logic necessary to create a list of possible alarm time values
/// for the provided `ArrivalDeparture`.
class AlarmTimePickerManager: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {

    private let pickerItems: [Int]

    private let arrivalDeparture: ArrivalDeparture

    /// The lead time to pre-select when the picker is displayed: the user's
    /// default alarm lead time, or the current alarm's lead time in the
    /// change-alarm flow.
    private let initialMinutes: Int

    lazy var pickerView: UIPickerView = {
        let picker = UIPickerView(frame: .zero)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.delegate = self
        picker.dataSource = self
        return picker
    }()

    init(arrivalDeparture: ArrivalDeparture, initialMinutes: Int) {
        self.arrivalDeparture = arrivalDeparture
        self.initialMinutes = initialMinutes
        self.pickerItems = AlarmTimePickerManager.incrementsForDeparture(arrivalDeparture.arrivalDepartureMinutes)
    }

    /// Configures the picker view's default value: the increment closest to
    /// `initialMinutes` (exact match when the value came from an increment).
    func prepareForDisplay() {
        let row = pickerItems.indices.min { abs(pickerItems[$0] - initialMinutes) < abs(pickerItems[$1] - initialMinutes) } ?? 0
        pickerView.selectRow(row, inComponent: 0, animated: false)
    }

    /// `nil` when the picker has no rows to select — a departure less than two
    /// minutes out has no valid lead time, and `UIPickerView` reports row -1.
    var selectedMinutes: Int? {
        let row = pickerView.selectedRow(inComponent: 0)
        guard pickerItems.indices.contains(row) else { return nil }
        return pickerItems[row]
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
