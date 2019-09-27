//
//  StopProblemViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/15/19.
//

import UIKit
import Eureka
import SVProgressHUD
import OBAKitCore

// TODO: this seems...busted. I can't figure out when this
// initializer will actually be called, though. Do I even
// really need it?
extension StopProblemCode: InputTypeInitiable {
    public init?(string stringValue: String) {
        return nil
    }
}

class StopProblemViewController: FormViewController {
    private let application: Application
    private let stop: Stop

    init(application: Application, stop: Stop) {
        self.application = application
        self.stop = stop
        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("stop_problem_controller.title", value: "Report a Problem", comment: "Title for the Report Stop Problem controller")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        form
        // Problem Section
        +++ Section(NSLocalizedString("stop_problem_controller.problem_section.section_title", value: "What seems to be the problem?", comment: "Title of the first section in the Stop Problem Controller."))
        <<< PickerInputRow<StopProblemCode>("stopProblemCode") {
            $0.title = NSLocalizedString("stop_problem_controller.problem_section.row_label", value: "Pick one:", comment: "Title label for the 'choose a problem type' row.")

            $0.options = StopProblemCode.allCases
            $0.value = $0.options.first
            $0.displayValueFor = { code -> String? in
                guard let code = code else { return nil }
                return stopProblemCodeToUserFacingString(code)
            }
        }

        // Comments Section
        +++ Section(NSLocalizedString("stop_problem_controller.comments_section.section_title", value: "Additional comments (optional)", comment: "The section header to a free-form comments field that the user does not have to add text to in order to submit this form."))
        <<< TextAreaRow(tag: "comments")

        // Button Section
        +++ Section()
        <<< ButtonRow {
            $0.title = NSLocalizedString("stop_problem_controller.send_button", value: "Send Message", comment: "The 'send' button that actually sends along the problem report.")
            $0.onCellSelection { [weak self] (_, _) in
                guard let self = self else { return }
                self.submitForm()
            }
        }
    }

    private func submitForm() {
        guard
            let codeRow = form.rowBy(tag: "stopProblemCode") as? PickerInputRow<StopProblemCode>,
            let commentRow = form.rowBy(tag: "comments") as? TextAreaRow,
            let stopProblemCode = codeRow.value,
            let modelService = application.restAPIModelService else { return }

        let location = application.locationService.currentLocation

        SVProgressHUD.show()

        let op = modelService.getStopProblem(stopID: stop.id, code: stopProblemCode, comment: commentRow.value, location: location)
        op.then { [weak self] in
            guard let self = self else { return }

            if let error = op.error {
                AlertPresenter.show(error: error, presentingController: self)
                SVProgressHUD.dismiss()
            }
            else {
                SVProgressHUD.showSuccessAndDismiss()
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
}
