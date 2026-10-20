//
//  MapPanelPrompts.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import SwiftUI
import UIKit
import OBAKitCore

/// The map's two prompts, as `MapViewController` runs them on the UIKit map: the
/// map survey's launcher card, and the feedback prompt a beat after a stop sheet
/// closes.
@MainActor
final class MapPanelPrompts: ObservableObject {

    /// The map survey whose launcher card is up, if any.
    @Published private(set) var survey: Survey?

    private let application: Application
    private let mapViewModel: MapViewModel
    private let presentingController: () -> UIViewController?
    private lazy var feedbackPromptPresenter = FeedbackPromptPresenter(application: application)
    private var feedbackPromptTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        application: Application,
        mapViewModel: MapViewModel,
        presentingController: @escaping () -> UIViewController?
    ) {
        self.application = application
        self.mapViewModel = mapViewModel
        self.presentingController = presentingController

        mapViewModel.surveyToPresent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] survey in self?.present(survey) }
            .store(in: &cancellables)
    }

    /// Checks for a map survey, once per session, as the UIKit map does when it
    /// appears.
    func checkForSurvey() {
        Task { [mapViewModel] in await mapViewModel.checkForSurveyPrompt() }
    }

    // MARK: - Survey

    private func present(_ survey: Survey) {
        // A stray double emit while a card is up: report it unshown, so the view
        // model rolls its session flag back and a later check can emit again.
        guard self.survey == nil else {
            mapViewModel.didPresentSurveyPrompt(survey, presented: false)
            return
        }
        self.survey = survey
        mapViewModel.didPresentSurveyPrompt(survey, presented: true)
    }

    /// The card's title: an external survey's hero question, as on the UIKit map.
    var surveyTitle: String? {
        guard let survey else { return nil }
        if survey.isExternalSurvey, let hero = survey.heroQuestion {
            return hero.content.labelText
        }
        return survey.name
    }

    func takeSurvey() {
        guard let survey else { return }
        if survey.isExternalSurvey {
            ExternalSurveyLauncher(surveyService: application.surveyService).launch(
                survey: survey,
                stop: nil,
                onSuccess: { [weak self] in self?.survey = nil },
                onFailure: { [weak self] in
                    self?.survey = nil
                    self?.showExternalSurveyError()
                }
            )
        } else {
            let controller = SurveyViewController(survey: survey, surveyService: application.surveyService)
            presentingController()?.present(UINavigationController(rootViewController: controller), animated: true)
            self.survey = nil
        }
    }

    func dismissSurvey() {
        guard let survey else { return }
        application.surveyService.markSurveyForLater(survey)
        application.surveyService.setNextReminderDate()
        self.survey = nil
    }

    private func showExternalSurveyError() {
        presentingController()?.present(ExternalSurveyLauncher.errorAlert(), animated: true)
    }

    // MARK: - Feedback prompt

    /// Whether the rider just closed a stop sheet and is back on the map: the
    /// natural stopping point the UIKit map asks for feedback at.
    ///
    /// - Parameters:
    ///   - previous: The stacked routes before the change.
    ///   - current: The stacked routes after it.
    nonisolated static func endsStopVisit(previous: [AppSheetRoute], current: [AppSheetRoute]) -> Bool {
        let hadStop = previous.contains { if case .stopDetails = $0 { true } else { false } }
        return hadStop && current.isEmpty
    }

    /// Arms the feedback prompt a second after a stop sheet closes, and cancels
    /// it when anything opens in the meantime. The delay keeps the alert from
    /// racing the sheet's dismissal, as on the UIKit map.
    func stackedRoutesChanged(from previous: [AppSheetRoute], to current: [AppSheetRoute]) {
        feedbackPromptTask?.cancel()
        feedbackPromptTask = nil
        guard Self.endsStopVisit(previous: previous, current: current) else { return }

        feedbackPromptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled,
                  let host = self.presentingController() else { return }
            self.feedbackPromptPresenter.presentIfEligible(from: host) { [weak self] in
                UIApplication.shared.applicationState == .active && self?.survey == nil
            }
        }
    }
}

/// The map survey's launcher card, floating above the panel's sheet as the
/// UIKit map floats `SurveyLauncherCardView` above its panel.
struct MapSurveyCard: View {
    let title: String
    let onTakeSurvey: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(OBALoc("survey_launcher.not_now_button", value: "Not now", comment: "Secondary button on the survey launcher card; dismisses the prompt."), action: onDismiss)
                    .buttonStyle(.bordered)
                Spacer()
                Button(OBALoc("survey_launcher.take_survey_button", value: "Take survey", comment: "Primary button on the survey launcher card; opens the survey."), action: onTakeSurvey)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}

/// Wires `MapPanelPrompts` into `MapPanelRootView` as one modifier, so the root's
/// long modifier chain stays within what the type checker handles.
struct MapPanelPromptsModifier: ViewModifier {
    @ObservedObject var prompts: MapPanelPrompts
    let stackedRoutes: [AppSheetRoute]
    let sheetHeight: CGFloat
    let toolbarsOpacity: CGFloat
    let toolbarsAnimationDuration: CGFloat

    func body(content: Content) -> some View {
        content
            .onAppear { prompts.checkForSurvey() }
            .onChange(of: stackedRoutes) { previous, current in
                prompts.stackedRoutesChanged(from: previous, to: current)
            }
            .overlay(alignment: .bottom) {
                if let title = prompts.surveyTitle, stackedRoutes.isEmpty {
                    MapSurveyCard(title: title, onTakeSurvey: prompts.takeSurvey, onDismiss: prompts.dismissSurvey)
                        .floatingOverSheet(height: sheetHeight, opacity: toolbarsOpacity, duration: toolbarsAnimationDuration)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.3), value: prompts.surveyTitle)
    }
}
