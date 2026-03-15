//
//  LiveActivityDurationPicker.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import BLTNBoard
import OBAKitCore
import UIKit

// MARK: - LiveActivityBuilder

/// Manages the bulletin lifecycle for starting a Live Activity.
/// Mirrors the `AlarmBuilder` pattern.
@available(iOS 16.2, *)
class LiveActivityBuilder: NSObject {

    private let bookmark: Bookmark
    private let arrivalDeparture: ArrivalDeparture
    private let manager: LiveActivityManager

    /// Called after the activity is successfully started.
    var onActivityStarted: VoidBlock?

    lazy var bulletinManager: BLTNItemManager = {
        let mgr = BLTNItemManager(rootItem: pickerPage)
        mgr.edgeSpacing = .compact
        return mgr
    }()

    private lazy var pickerPage: LiveActivityDurationPickerItem = {
        let page = LiveActivityDurationPickerItem(
            bookmark: bookmark,
            arrivalDeparture: arrivalDeparture,
            manager: manager
        )
        page.actionHandler = { [weak self] _ in
            guard let self else { return }
            let duration = self.pickerPage.selectedDuration
            self.manager.preferredDuration = duration
            Task {
                do {
                    if let activity = try await self.manager.startActivity(
                        for: self.bookmark,
                        arrivalDeparture: self.arrivalDeparture,
                        duration: duration
                    ) {
                        // Push map snapshot as a separate update after start —
                        // the initial payload must stay under ActivityKit's 4KB limit.
                        Task { await self.manager.pushMapSnapshot(to: activity) }
                    }
                    await MainActor.run {
                        self.bulletinManager.dismissBulletin(animated: true)
                        self.onActivityStarted?()
                    }
                } catch {
                    Logger.error("Failed to start Live Activity: \(error)")
                    await MainActor.run {
                        self.bulletinManager.dismissBulletin(animated: true)
                    }
                }
            }
        }
        return page
    }()

    init(bookmark: Bookmark, arrivalDeparture: ArrivalDeparture, manager: LiveActivityManager) {
        self.bookmark = bookmark
        self.arrivalDeparture = arrivalDeparture
        self.manager = manager
    }

    func showBulletin(above viewController: UIViewController) {
        guard !bulletinManager.isShowingBulletin else { return }
        bulletinManager.showBulletin(above: viewController)
    }
}

// MARK: - LiveActivityDurationPickerItem

/// The BLTNBoard page that shows a UIPickerView for selecting Live Activity duration.
@available(iOS 16.2, *)
class LiveActivityDurationPickerItem: ThemedBulletinPage, UIPickerViewDelegate, UIPickerViewDataSource {

    private let durations = LiveActivityManager.Duration.allCases
    private let liveActivityManager: LiveActivityManager

    lazy var pickerView: UIPickerView = {
        let picker = UIPickerView(frame: .zero)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.delegate = self
        picker.dataSource = self
        return picker
    }()

    var selectedDuration: LiveActivityManager.Duration {
        durations[pickerView.selectedRow(inComponent: 0)]
    }

    init(bookmark: Bookmark, arrivalDeparture: ArrivalDeparture, manager: LiveActivityManager) {
        self.liveActivityManager = manager

        let routeShortName = bookmark.routeShortName ?? ""
        let headsign = bookmark.tripHeadsign ?? ""

        super.init(title: OBALoc(
            "live_activity.bulletin.title",
            value: "Start Live Activity",
            comment: "Title for the Live Activity duration picker bulletin"
        ))

        descriptionText = "\(routeShortName) – \(headsign)\n\(bookmark.stop.name)"
        isDismissable = true
        actionButtonTitle = OBALoc(
            "live_activity.bulletin.start_button",
            value: "Start",
            comment: "Start button in the Live Activity bulletin"
        )
    }

    func prepareForDisplay() {
        let defaultIndex = durations.firstIndex(of: liveActivityManager.preferredDuration) ?? 3
        pickerView.selectRow(defaultIndex, inComponent: 0, animated: false)
    }

    override func makeViewsUnderDescription(with interfaceBuilder: BLTNInterfaceBuilder) -> [UIView]? {
        prepareForDisplay()
        return [pickerView]
    }

    // MARK: - UIPickerViewDataSource

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        durations.count
    }

    // MARK: - UIPickerViewDelegate

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        durations[row].localizedTitle
    }
}
