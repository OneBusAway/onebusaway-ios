//
//  SurveyPrioritizerTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 06/12/2025.
//

import XCTest
import OBAKitCore
import Nimble

final class SurveyPrioritizerTests: OBATestCase {

    private var stops: [Stop]!

    override func setUp() {
        super.setUp()
        stops = try! Fixtures.loadRESTAPIPayload(type: [Stop].self, fileName: "stops_for_surveys.json")
    }

    func test_nextSurveyIndex_whenSurveysEmpty_returnsNoIndex() {
        let index = surveyPrioritizer.nextSurveyIndex([], visibleOnStop: true, stop: nil)
        expect(index).to(equal(-1))
    }

    func test_nextSurveyIndex_whenNoQuestions_returnsNoIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, showOnStops: false),
            makeSurvey(id: 1, showOnMap: false),
        ]
        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(-1))
    }

    func test_nextSurveyIndex_whenMapContextVisible_returnsCorrectIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, showOnStops: false),
            makeSurvey(id: 1, showOnMap: false),
            makeSurvey(id: 2, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: false, stop: nil)
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenStopContextVisible_returnsCorrectIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0),
            makeSurvey(id: 1),
            makeSurvey(id: 2, showOnMap: false, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenAllSurveysHidden_returnsNoIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, showOnMap: false, showOnStops: false, questions: makeQuestions()),
            makeSurvey(id: 1, showOnMap: false, showOnStops: false, questions: makeQuestions()),
            makeSurvey(id: 2, showOnMap: false, showOnStops: false, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(-1))
    }

    // MARK: - MapContext
    func test_nextSurveyIndex_whenMapContextEmptyQuestions_returnsIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0),
            makeSurvey(id: 1),
            makeSurvey(id: 2, showOnStops: false, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: false, stop: nil)
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenMapContext_returnsFirstVisible() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, showOnStops: false, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, showOnMap: false, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, showOnStops: false, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: false, stop: nil)
        expect(index).to(equal(0))
    }

    func test_nextSurveyIndex_whenMapContextNoVisibleSurveys_returnsNoIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, showOnMap: false, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, showOnMap: false, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, showOnMap: false, questions: makeQuestions()),
            makeSurvey(id: 3, showOnMap: false, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: false, stop: nil)
        expect(index).to(equal(-1))
    }

    // MARK: - StopContext
    func test_nextSurveyIndex_whenStopContextEmptyLists_returnsIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, showOnStops: false, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(1))
    }

    func test_nextSurveyIndex_whenStopContextNil_returnsNoIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: nil)
        expect(index).to(equal(-1))
    }

    func test_nextSurveyIndex_whenStopContextStopInList_returnsIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_A", "STOP_B"], questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_A"], questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_D"], questions: makeQuestions())
        ]

        let stop = stops[3] // id = "STOP_D"

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stop)
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenStopContextStopNotInList_returnsNoIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_A", "STOP_B"], questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_A"], questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_X"], questions: makeQuestions())
        ]

        let stop = stops[3] // id = "STOP_D"

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stop)
        expect(index).to(equal(-1))
    }

    func test_nextSurveyIndex_whenStopContextRouteMatch_returnsIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_A", "STOP_B"], routesList: ["1_300", "1_311"], questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_A"], routesList: ["1_309", "1_315"], questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_X"], routesList: ["1_30", "1_31"],  questions: makeQuestions())
        ]

        let stop = stops[3] // id = "STOP_D"

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stop)
        expect(index).to(equal(1))
    }

    func test_nextSurveyIndex_whenStopContextRouteAndStopMatch_returnsIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_A", "STOP_B"], routesList: ["1_300", "1_311"], questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_D", "STOP_A"], routesList: ["1_309", "1_315"], questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_X"], routesList: ["1_309", "1_31"],  questions: makeQuestions())
        ]

        let stop = stops[3] // id = "STOP_D"

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stop)
        expect(index).to(equal(1))
    }

    func test_nextSurveyIndex_whenStopContextNoMatch_returnsNoIndex() {
        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_A", "STOP_B"], routesList: ["1_300", "1_311"], questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_A"], routesList: ["1_314", "1_315"], questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_X"], routesList: ["1_30", "1_31"],  questions: makeQuestions())
        ]

        let stop = stops[3] // id = "STOP_D"

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stop)
        expect(index).to(equal(-1))
    }

    // MARK: - Classification

        // MARK: - AlwaysVisible
    func test_nextSurveyIndex_whenAlwaysVisibleNotCompleted_returnsIndex() {

        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0], skippedSurveyIDs: [1]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 3, questions: makeQuestions()),
            makeSurvey(id: 4, multipleResponses: true, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenAlwaysVisibleAllCompleted_returnsNoIndex() {

        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 3, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(-1))
    }

    func test_nextSurveyIndex_whenAlwaysVisibleAllSkipped_returnsNoIndex() {

        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(skippedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 3, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(-1))
    }

        // MARK: - MultipleResponses
    func test_nextSurveyIndex_whenMultipleResponsesNotCompleted_returnsIndex() {

        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0,2], skippedSurveyIDs: [1]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 3, multipleResponses: true, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 4, multipleResponses: true, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(3))
    }

    func test_nextSurveyIndex_whenMultipleResponsesAllCompleted_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 3, multipleResponses: true, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(3))
    }

    func test_nextSurveyIndex_whenMultipleResponsesAllSkipped_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(skippedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 3, multipleResponses: true, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(2))
    }

        // MARK: - NotAlwaysVisible

    func test_nextSurveyIndex_whenNotAlwaysVisibleNotCompleted_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 3, multipleResponses: true, allowsVisible: true, questions: makeQuestions()),
            makeSurvey(id: 2, allowsVisible: true, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(1))
    }

    func test_nextSurveyIndex_whenNotAlwaysVisibleAllCompleted_returnsNoIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 3, questions: makeQuestions()),
            makeSurvey(id: 2, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(-1))
    }

    func test_nextSurveyIndex_whenNotAlwaysVisibleAllSkipped_returnsNoIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(skippedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, questions: makeQuestions(count: 4)),
            makeSurvey(id: 3, questions: makeQuestions()),
            makeSurvey(id: 2, questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[0])
        expect(index).to(equal(-1))
    }

    // MARK: - Prioritization

        // MARK: - StopOverlap
    func test_nextSurveyIndex_whenStopOverlapSingleAlwaysVisible_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_C", "STOP_F"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_C", "STOP_A"], questions: makeQuestions()),
            makeSurvey(id: 3, stopList: ["STOP_F", "STOP_A"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(1))
    }

    func test_nextSurveyIndex_whenStopOverlapIncompleteSurvey_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [1, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_C", "STOP_F"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_C", "STOP_A"], questions: makeQuestions()),
            makeSurvey(id: 3, stopList: ["STOP_F", "STOP_A"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenStopOverlapMultipleAlwaysVisible_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [1, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_C", "STOP_F"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 3, stopList: ["STOP_F", "STOP_A"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(0))
    }

    func test_nextSurveyIndex_whenStopOverlapAllCompleted_returnsNoIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 1, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 3, stopList: ["STOP_F", "STOP_A"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(-1))
    }

        // MARK: - RouteOverlap
    func test_nextSurveyIndex_whenRouteOverlapSingleAlwaysVisible_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, routesList: ["1_309", "1_350"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, routesList: ["1_309", "1_351"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, routesList: ["1_309", "1_310"], questions: makeQuestions()),
            makeSurvey(id: 3, routesList: ["1_311", "1_312"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(1))
    }

    func test_nextSurveyIndex_whenRouteOverlapIncompleteSurvey_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [1, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, routesList: ["1_309", "1_350"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, routesList: ["1_309", "1_351"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, routesList: ["1_309", "1_310"], questions: makeQuestions()),
            makeSurvey(id: 3, routesList: ["1_311", "1_312"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(2))
    }

    func test_nextSurveyIndex_whenRouteOverlapMultipleAlwaysVisible_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, routesList: ["1_309", "1_350"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, routesList: ["1_309", "1_351"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, routesList: ["1_309", "1_310"], questions: makeQuestions()),
            makeSurvey(id: 3, routesList: ["1_311", "1_312"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(0))
    }

    func test_nextSurveyIndex_whenRouteOverlapAllCompleted_returnsNoIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [0, 1, 2, 3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, routesList: ["1_309", "1_350"], allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, routesList: ["1_309", "1_310"], questions: makeQuestions()),
            makeSurvey(id: 3, routesList: ["1_311", "1_312"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(-1))
    }

        // MARK: - StopRouteOverlap

    func test_nextSurveyIndex_whenStopRouteOverlapSingleAlwaysVisible_returnsIndex() {
        let surveyPref = surveyPrioritizer.surveyStore
        surveyPref.setSurveyPreferences(.init(completedSurveyIDs: [3]))

        let surveys: [Survey] = [
            makeSurvey(id: 0, routesList: ["1_309", "1_350"], multipleResponses: true, allowsVisible: true, questions: makeQuestions(count: 5)),
            makeSurvey(id: 1, stopList: ["STOP_C", "STOP_F"], allowsVisible: true, questions: makeQuestions(count: 4)),
            makeSurvey(id: 2, stopList: ["STOP_D", "STOP_F"], questions: makeQuestions()),
            makeSurvey(id: 3, routesList: ["1_309", "1_312"], questions: makeQuestions())
        ]

        let index = surveyPrioritizer.nextSurveyIndex(surveys, visibleOnStop: true, stop: stops[2])
        expect(index).to(equal(1))
    }

}

// MARK: - Helper
extension SurveyPrioritizerTests {

    func makeSurvey(
        id: Int = 1,
        name: String = "Survey",
        showOnMap: Bool = true,
        showOnStops: Bool = true,
        stopList: [String]? = nil,
        routesList: [String]? = nil,
        multipleResponses: Bool = false,
        allowsVisible: Bool = false,
        study: Study? = nil,
        questions: [SurveyQuestion] = []
    ) -> Survey {

        var studyModel = Study(id: 1, name: "Study", description: "Description")

        if let study {
            studyModel = study
        }

        return .init(
            id: id,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: showOnMap,
            showOnStops: showOnStops,
            startDate: Date(),
            endDate: Date(),
            visibleStopsList: stopList,
            visibleRoutesList: routesList,
            allowsMultipleResponses: multipleResponses,
            allowsVisible: allowsVisible,
            study: studyModel,
            questions: questions
        )
    }

    func makeQuestions(count: Int = 3) -> [SurveyQuestion] {
        (0..<count).map { index in
            SurveyQuestion(
                id: index + 1,
                position: index,
                required: false,
                content: QuestionContent(
                    labelText: "Question \(index + 1)",
                    type: .text
                )
            )
        }
    }

}
