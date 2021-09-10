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

    // TODO: this feature may be expanded to make better use of
    // system resources. For now, this will avoid initializing
    // certain feedback generators to save power. For example,
    // we may never need `notificationFeedback` if there is
    // never an error.
    fileprivate var selectionFeedback: UISelectionFeedbackGenerator?
    fileprivate var notificationFeedback: UINotificationFeedbackGenerator?

    init() { }

    func dataLoad(_ feedback: FeedbackType) {
        switch feedback {
        case .success: dataLoadSuccess()
        case .failed:  dataLoadFailed()
        }
    }

    fileprivate func dataLoadSuccess() {
        // TODO: Until https://github.com/oneBusAway/onebusaway-ios/issues/505
        // is fixed, this has been disabled.

        // if selectionFeedback == nil {
        //     selectionFeedback = UISelectionFeedbackGenerator()
        // }
        //
        // selectionFeedback?.selectionChanged()
        // selectionFeedback = nil
    }

    fileprivate func dataLoadFailed() {
        // TODO: Until https://github.com/oneBusAway/onebusaway-ios/issues/505
        // is fixed, this has been disabled.

        // if notificationFeedback == nil {
        //     notificationFeedback = UINotificationFeedbackGenerator()
        // }
        //
        // notificationFeedback?.notificationOccurred(.error)
        // notificationFeedback = nil
    }
}
