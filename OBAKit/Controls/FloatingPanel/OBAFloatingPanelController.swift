//
//  OBAFloatingPanelController.swift
//  OBAKit
//
//  Created by Alan Chu on 8/3/21.
//

import FloatingPanel

/// A subclass of `FloatingPanelController` with additional accessibility features.
class OBAFloatingPanelController: FloatingPanelController {
    static let UserHasSeenFullSheetVoiceoverChangeUserDefaultsKey = "OBAFloatingPanelController.userHasSeenFullSheetVoiceoverChange"
    static let AlwaysShowFullSheetOnVoiceoverUserDefaultsKey = "OBAFloatingPanelController.alwaysShowFullSheetVoiceover"

    let userDefaults: UserDefaults

    /// Flag for displaying an alert informing the user that VoiceOver will automatically
    /// display the full sheet and ignore map elements.
    var userHasSeenFullSheetVoiceoverChange: Bool {
        get { userDefaults.bool(forKey: OBAFloatingPanelController.UserHasSeenFullSheetVoiceoverChangeUserDefaultsKey) }
        set { userDefaults.set(newValue, forKey: OBAFloatingPanelController.UserHasSeenFullSheetVoiceoverChangeUserDefaultsKey) }
    }

    var alwaysShowFullSheetOnVoiceover: Bool {
        userDefaults.bool(forKey: OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey)
    }

    init(_ application: Application, delegate: FloatingPanelControllerDelegate?) {
        userDefaults = application.userDefaults

        super.init(delegate: delegate)

        surfaceView.grabberHandle.accessibilityLabel = OBALoc("floating_panel.controller.accessibility_label", value: "Card controller", comment: "A voiceover title describing the 'grabber' for controlling the visibility of a card.")

        let expandName = OBALoc("floating_panel.controller.expand_action_name", value: "Expand", comment: "A voiceover title describing the action to expand the visibility of a card.")
        let collapseName = OBALoc("floating_panel.controller.collapse_action_name", value: "Collapse", comment: "A voiceover title describing the action to minimize (or collapse) the visibility of a card.")
        let expandAction = UIAccessibilityCustomAction(name: expandName, target: self, selector: #selector(accessibilityActionExpandPanel))
        let collapseAction = UIAccessibilityCustomAction(name: collapseName, target: self, selector: #selector(accessibilityActionCollapsePanel))

        surfaceView.grabberHandle.accessibilityCustomActions = [expandAction, collapseAction]
        surfaceView.grabberHandle.isAccessibilityElement = true
        updateAccessibilityValue()

        userDefaults.register(defaults: [
            OBAFloatingPanelController.AlwaysShowFullSheetOnVoiceoverUserDefaultsKey: true,
            OBAFloatingPanelController.UserHasSeenFullSheetVoiceoverChangeUserDefaultsKey: false
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    func fullSheetVoiceoverAlert() -> UIAlertController {
        let title = OBALoc("floating_panel.controller.full_sheet_voiceover_change_alert.title", value: "Voiceover detected", comment: "")
        let message = OBALoc("floating_panel.controller.full_sheet_voiceover_change_alert.message", value: "The sheet will automatically expand when VoiceOver is turned on. To disable this behavior, visit the Settings page.", comment: "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(.dismissAction)

        return alert
    }

    private func updateAccessibilityValue() {
        let accessibilityValue: String?
        switch self.state {
        case .full:
            accessibilityValue = OBALoc("floating_panel.controller.position.full", value: "Full screen", comment: "A voiceover title describing that the card's visibility is taking up the full screen.")
        case .half:
            accessibilityValue = OBALoc("floating_panel.controller.position.half", value: "Half screen", comment: "A voiceover title describing that the card's visibility is taking up half of the screen.")
        case .tip:
            accessibilityValue = OBALoc("floating_panel.controller.position.minimized", value: "Minimized", comment: "A voiceover title describing that the card's visibility taking up the minimum amount of screen.")
        case .hidden:
            accessibilityValue = nil
        default:
            accessibilityValue = String(describing: state)
        }

        surfaceView.grabberHandle.accessibilityValue = accessibilityValue
    }

    @objc private func accessibilityActionExpandPanel() -> Bool {
        let availableAnchors = self.layout.anchors

        guard let currentAnchorIndex = availableAnchors.index(forKey: self.state),
              let newAnchorIndex = availableAnchors.index(currentAnchorIndex, offsetBy: 1, limitedBy: availableAnchors.endIndex) else {
            return false
        }

        self.move(to: availableAnchors[newAnchorIndex].key, animated: true) { [weak self] in
            self?.updateAccessibilityValue()
        }

        return true
    }

    @objc private func accessibilityActionCollapsePanel() -> Bool {
        let availableAnchors = self.layout.anchors

        guard let currentAnchorIndex = availableAnchors.index(forKey: self.state),
              let newAnchorIndex = availableAnchors.index(currentAnchorIndex, offsetBy: -1, limitedBy: availableAnchors.endIndex) else {
            return false
        }

        self.move(to: availableAnchors[newAnchorIndex].key, animated: true) { [weak self] in
            self?.updateAccessibilityValue()
        }

        return true
    }
}
