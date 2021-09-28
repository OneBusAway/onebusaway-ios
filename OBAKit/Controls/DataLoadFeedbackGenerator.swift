//
//  DataLoadFeedbackGenerator.swift
//  OBAKit
//
//  Created by Alan Chu on 8/12/21.
//

/// Provides appropriate haptic feedback depending on a data load result.
/// This class DRYs lifecycle management of the system's Feedback Generators and
/// standardizes haptic feedback across the app.
class DataLoadFeedbackGenerator {
    enum FeedbackType {
        case success
        case failed
    }
    static let EnabledUserDefaultsKey = "DataLoadFeedbackGenerator.enabled"

    private let userDefaults: UserDefaults
    private var isUserEnabled: Bool {
        userDefaults.bool(forKey: DataLoadFeedbackGenerator.EnabledUserDefaultsKey)
    }

    // TODO: this feature may be expanded to make better use of
    // system resources. For now, this will avoid initializing
    // certain feedback generators to save power. For example,
    // we may never need `notificationFeedback` if there is
    // never an error.
    fileprivate var selectionFeedback: UISelectionFeedbackGenerator?
    fileprivate var notificationFeedback: UINotificationFeedbackGenerator?

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [DataLoadFeedbackGenerator.EnabledUserDefaultsKey: true])
    }

    convenience init(application: Application) {
        self.init(userDefaults: application.userDefaults)
    }

    func dataLoad(_ feedback: FeedbackType) {
        switch feedback {
        case .success: dataLoadSuccess()
        case .failed:  dataLoadFailed()
        }
    }

    fileprivate func dataLoadSuccess() {
        guard isUserEnabled else { return }
        if selectionFeedback == nil {
            selectionFeedback = UISelectionFeedbackGenerator()
        }

        selectionFeedback?.selectionChanged()
        selectionFeedback = nil
    }

    fileprivate func dataLoadFailed() {
        guard isUserEnabled else { return }
        if notificationFeedback == nil {
            notificationFeedback = UINotificationFeedbackGenerator()
        }

        notificationFeedback?.notificationOccurred(.error)
        notificationFeedback = nil
    }
}
