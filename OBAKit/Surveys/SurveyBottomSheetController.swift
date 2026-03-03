//
//  SurveyBottomSheetController.swift
//  OBAKit 
//
//  Copyright Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import FloatingPanel
import OBAKitCore

class SurveyBottomSheetController: FloatingPanelController {
    private let survey: Survey
    private let surveyService: SurveyService
    private let stopID: String?
    private let stopLocation: (latitude: Double, longitude: Double)?

    init(
        survey: Survey,
        surveyService: SurveyService,
        stopID: String? = nil,
        stopLocation: (latitude: Double, longitude: Double)? = nil
    ) {
        self.survey = survey
        self.surveyService = surveyService
        self.stopID = stopID
        self.stopLocation = stopLocation

        super.init(delegate: nil)

        setupBottomSheet()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBottomSheet() {
        delegate = self

        let surveyVC = SurveyViewController(
            survey: survey,
            surveyService: surveyService,
            stopID: stopID,
            stopLocation: stopLocation
        )
        let navigationController = UINavigationController(rootViewController: surveyVC)
        set(contentViewController: navigationController)

        layout = SurveyBottomSheetLayout()
        behavior = SurveyBottomSheetBehavior()

        let appearance = SurfaceAppearance()
        appearance.cornerRadius = 16
        appearance.backgroundColor = .systemBackground
        surfaceView.appearance = appearance

        surfaceView.contentView?.layer.shadowColor = UIColor.black.cgColor
        surfaceView.contentView?.layer.shadowOpacity = 0.1
        surfaceView.contentView?.layer.shadowOffset = CGSize(width: 0, height: -2)
        surfaceView.contentView?.layer.shadowRadius = 8

        backdropView.dismissalTapGestureRecognizer.isEnabled = true
        surfaceView.grabberHandle.isHidden = false
        surfaceView.grabberHandle.barColor = .systemGray3
        isRemovalInteractionEnabled = true
    }
}

// MARK: - FloatingPanelControllerDelegate
extension SurveyBottomSheetController: FloatingPanelControllerDelegate {

    func floatingPanelDidChangeState(_ fpc: FloatingPanelController) {
        // Handle state changes if needed
        let state = fpc.state

        switch state {
        case .hidden:
            // Panel was dismissed by swipe
            dismiss(animated: false)
        default:
            break
        }
    }

    func floatingPanelWillEndDragging(_ fpc: FloatingPanelController, withVelocity velocity: CGPoint, targetState: UnsafeMutablePointer<FloatingPanelState>) {
        let currentY = fpc.surfaceLocation.y
        let panelHeight = fpc.surfaceView.bounds.height

        if velocity.y > 500 || currentY > panelHeight * 0.6 {
            targetState.pointee = .hidden
        }
    }
}

// MARK: - Custom Layout
class SurveyBottomSheetLayout: FloatingPanelLayout {

    let position: FloatingPanelPosition = .bottom
    let initialState: FloatingPanelState = .half

    var anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] {
        return [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 16.0, edge: .top, referenceGuide: .safeArea),
            .half: FloatingPanelLayoutAnchor(fractionalInset: 0.5, edge: .bottom, referenceGuide: .safeArea),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 88.0, edge: .bottom, referenceGuide: .safeArea),
            .hidden: FloatingPanelLayoutAnchor(absoluteInset: 0, edge: .bottom, referenceGuide: .superview)
        ]
    }

    func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        switch state {
        case .full: return 0.3
        case .half: return 0.1
        case .tip: return 0.0
        case .hidden: return 0.0
        default: return 0.0
        }
    }
}

// MARK: - Custom Behavior
class SurveyBottomSheetBehavior: FloatingPanelBehavior {

    let springDecelerationRate: CGFloat = UIScrollView.DecelerationRate.fast.rawValue
    let springResponseTime: CGFloat = 0.4

    func interactionAnimator(_ fpc: FloatingPanelController, to targetState: FloatingPanelState, with velocity: CGVector) -> UIViewPropertyAnimator {
        let timing = UISpringTimingParameters(mass: 1.0, stiffness: 500, damping: 30, initialVelocity: velocity)
        return UIViewPropertyAnimator(duration: 0.0, timingParameters: timing)
    }

    func shouldProjectMomentum(_ fpc: FloatingPanelController, for proposedTargetPosition: CGPoint) -> Bool {
        return true
    }

    func redirectionalProgress(_ fpc: FloatingPanelController, from: FloatingPanelState, to: FloatingPanelState) -> CGFloat {
        return 0.5
    }

    func allowsRubberBanding(for edge: UIRectEdge) -> Bool {
        return edge == .bottom
    }
}
