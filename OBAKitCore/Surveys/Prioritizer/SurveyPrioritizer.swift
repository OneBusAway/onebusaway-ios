//
//  SurveyPrioritizer.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 29/11/2025.
//

import Foundation

/// Responsible for selecting/prioritizing which survey to show to the user based on visibility, completion, and survey type.
public class SurveyPrioritizer: SurveyPrioritizing {

    public var surveyStore: SurveyPreferencesStore

    /// Cached lists of completed and skipped survey IDs.
    private var handledSurveyIDs: Set<Int> {
        let preferences = surveyStore.surveyPreferences()
        return preferences.skippedSurveyIDs.union(preferences.completedSurveyIDs)
    }

    // MARK: - Initialization

    /// Initializes a new SurveyPrioritizer with a survey store.
    /// - Parameter surveyStore: Store containing survey preferences and completed surveys.
    public init(surveyStore: SurveyPreferencesStore) {
        self.surveyStore = surveyStore
    }

    // MARK: - Public Methods

    /// Returns the index of the next survey to show based on priority.
    ///
    /// Priority order:
    /// 1. Always visible, single-use, not completed → returned immediately
    /// 2. One-time incomplete survey
    /// 3. Always visible, multiple-response survey
    /// 4. Completed surveys → ignored
    ///
    /// - Parameters:
    ///   - surveys: List of surveys to prioritize.
    ///   - visibleOnStop: Whether the current context is a stop.
    ///   - stop: Optional stop to check visibility against.
    /// - Returns: Index of the survey to show, or -1 if none available.
    public func nextSurveyIndex(_ surveys: [Survey], visibleOnStop: Bool = false, stop: Stop? = nil) -> Int {

        guard !surveys.isEmpty else { return -1 }

        var selectedSurveyIndex: Int = -1
        var selectedSurveyClassification: SurveyClassification = .completed

        for (index, survey) in surveys.enumerated() {

            // Skip surveys with no questions
            guard !survey.questions.isEmpty else { continue }

            // Skip surveys that should not be visible in the current context
            guard shouldShowSurvey(survey, visibleOnStop: visibleOnStop, stop: stop) else {
                continue
            }

            // Determine survey classification
            let classification = surveyClassification(for: survey)

            // Highest priority: always visible, single-use, not completed
            if classification == .alwaysVisibleOneTime {
                return index
            }

            // Track the best survey found
            if classification < selectedSurveyClassification {
                selectedSurveyIndex = index
                selectedSurveyClassification = classification
            }
        }

        return selectedSurveyIndex
    }

    // MARK: - Private Methods

    /// Determines whether a survey should be shown in the current context.
    /// - Parameters:
    ///   - survey: Survey to evaluate.
    ///   - visibleOnStop: Whether we are at a stop.
    ///   - stop: Optional stop for stop-specific visibility.
    /// - Returns: `true` if the survey should be shown, `false` otherwise.
    private func shouldShowSurvey(_ survey: Survey, visibleOnStop: Bool, stop: Stop?) -> Bool {

        // If survey is not shown on map or stops → skip
        guard survey.showOnMap || survey.showOnStops else { return false }

        if visibleOnStop && survey.showOnStops {
            // If at a stop, check stop-specific visibility
            return isSurveyVisible(on: stop, for: survey)
        } else if !visibleOnStop && survey.showOnMap {
            // If not at a stop (map context), show if map visibility is allowed
            return true
        }

        return false
    }

    /// Determines if a survey is visible at a specific stop.
    /// - Parameters:
    ///   - stop: Stop to check against.
    ///   - survey: Survey to check.
    /// - Returns: `true` if the survey should be visible at this stop.
    private func isSurveyVisible(on stop: Stop?, for survey: Survey) -> Bool {
        guard let stop else { return false }

        var stopListExistence: Bool = false
        var routeListExistence: Bool = false

        // If no stop or route restrictions → survey is visible
        if survey.visibleStopsList == nil && survey.visibleRoutesList == nil {
            return true
        }

        // Check if stop is explicitly listed
        if let stopList = survey.visibleStopsList {
            stopListExistence = stopList.contains(stop.id)
        }

        // Check if any of the stop's routes are listed
        if let routesList = survey.visibleRoutesList {
            routeListExistence = routesList.contains { routeId in
                stop.routes.contains(where: { $0.id == routeId })
            }
        }

        return stopListExistence || routeListExistence
    }

    /// Classifies a survey into a priority category.
    /// - Parameter survey: Survey to classify.
    /// - Returns: `SurveyClassification` indicating the survey's priority.
    private func surveyClassification(for survey: Survey) -> SurveyClassification {
        let completedOrSkipped = handledSurveyIDs.contains(survey.id)

        // If survey is not always visible → one-time incomplete
        if !survey.allowsVisible && !completedOrSkipped {
            return .oneTimeIncomplete
        }

        // Always visible surveys
        if survey.allowsVisible && survey.allowsMultipleResponses {
            return .alwaysVisibleMultiple
        } else if survey.allowsVisible && !completedOrSkipped {
            return .alwaysVisibleOneTime
        }

        return .completed
    }

}

// MARK: - SurveyClassification Enum

private extension SurveyPrioritizer {

    /// Represents the priority classification of a survey
    enum SurveyClassification: Int, Comparable {
        case alwaysVisibleOneTime = 0       // Highest priority: always visible, single-use, not completed
        case oneTimeIncomplete = 1          // Normal one-time incomplete survey
        case alwaysVisibleMultiple = 2      // Always visible, multi-response
        case completed = 3                  // Completed surveys, lowest priority

        static func < (lhs: SurveyClassification, rhs: SurveyClassification) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
