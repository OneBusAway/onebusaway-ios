//
//  MapPanelPromptsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The feedback prompt's only call site was the UIKit map, so riders on the
/// panel were never asked. The panel asks where the UIKit map does: back on the
/// map, a beat after a stop sheet closes.
@Suite
struct MapPanelPromptsTests {

    private let stop = AppSheetRoute.stopDetails(stopID: "1_75403")

    @Test func `Closing a stop sheet back to the map ends a stop visit`() {
        #expect(MapPanelPrompts.endsStopVisit(previous: [stop], current: [], closedByApp: false))
        #expect(MapPanelPrompts.endsStopVisit(previous: [.nearbyAll, stop], current: [], closedByApp: false))
    }

    @Test func `Anything still open, or no stop closed, is not a stopping point`() {
        #expect(!MapPanelPrompts.endsStopVisit(previous: [.nearbyAll, stop], current: [.nearbyAll], closedByApp: false))
        #expect(!MapPanelPrompts.endsStopVisit(previous: [.more], current: [], closedByApp: false))
        #expect(!MapPanelPrompts.endsStopVisit(previous: [], current: [stop], closedByApp: false))
    }

    /// A region change or a rentals link closes the sheets; the rider didn't
    /// finish with the stop.
    @Test func `The app closing the sheets is not a stopping point`() {
        #expect(!MapPanelPrompts.endsStopVisit(previous: [stop], current: [], closedByApp: true))
    }

    /// No flag to clear: the next close the rider makes counts again.
    @MainActor
    @Test func `The coordinator knows whose close it was`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        coordinator.push(stop)
        coordinator.popToRoot()
        #expect(coordinator.lastChangeWasPopToRoot)

        coordinator.push(stop)
        #expect(!coordinator.lastChangeWasPopToRoot)
        coordinator.pop()
        #expect(!coordinator.lastChangeWasPopToRoot)

        coordinator.popToRoot()
        coordinator.truncateStacked(toDepth: 0)
        #expect(!coordinator.lastChangeWasPopToRoot, "A drag-down is the rider's")

        coordinator.popToRoot()
        coordinator.open(stop, from: .home)
        #expect(!coordinator.lastChangeWasPopToRoot)
    }

    /// The card follows the sheet; nothing else in the modifier does.
    @Test func `With no card up a sheet drag doesn't change the modifier's inputs`() {
        let resting = MapPanelPromptsModifier.cardPlacement(sheetHeight: 120, toolbarsOpacity: 1, showsCard: false)
        let dragging = MapPanelPromptsModifier.cardPlacement(sheetHeight: 431.5, toolbarsOpacity: 0.4, showsCard: false)
        #expect(resting == dragging)

        let card = MapPanelPromptsModifier.cardPlacement(sheetHeight: 431.5, toolbarsOpacity: 0.4, showsCard: true)
        #expect(card == (431.5, 0.4))
    }
}

/// The survey card's rules, shared by both maps (#1623 follow-up).
@MainActor
@Suite(.serialized)
final class MapSurveyCardTests: OBATestCase {

    private func survey(external: Bool) -> Survey {
        let content = QuestionContent(labelText: "How was your ride?", type: external ? .externalSurvey : .text, url: external ? "https://example.com/s" : nil)
        return Survey(
            id: 7, name: "Rider survey", createdAt: Date(), updatedAt: Date(),
            showOnMap: true, showOnStops: false,
            startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(3600),
            visibleStopsList: nil, visibleRoutesList: nil,
            allowsMultipleResponses: false, alwaysVisible: false,
            study: Study(id: 1, name: "Study", description: "Description"),
            questions: [SurveyQuestion(id: 1, position: 1, required: false, content: content)]
        )
    }

    @Test func `An external survey's card asks its hero question, others show the name`() {
        #expect(survey(external: true).launcherTitle == "How was your ride?")
        #expect(survey(external: false).launcherTitle == "Rider survey")
    }

    @Test func `Not now holds the survey for later and sets the next reminder`() {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let service = SurveyService(apiService: nil, userDataStore: store)
        #expect(store.nextSurveyReminderDate == nil)

        service.postpone(survey(external: false))

        #expect(store.nextSurveyReminderDate != nil)
        #expect(!store.isSurveyCompleted(surveyId: 7, userIdentifier: store.surveyUserIdentifier))
    }

    /// With nothing to present from, the card stays rather than losing the survey.
    @Test func `Take survey keeps the card when nothing can present it`() {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))
        let mapViewModel = MapViewModel(application: application, initialMapType: .standard)
        let prompts = MapPanelPrompts(application: application, mapViewModel: mapViewModel, presentingController: { nil })
        prompts.present(survey(external: false))
        #expect(prompts.surveyTitle == "Rider survey")

        prompts.takeSurvey()

        #expect(prompts.surveyTitle == "Rider survey")
    }
}
