//
//  StopProblemViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/15/19.
//

import UIKit
import Eureka
import OBAKitCore

// This seems...busted. I can't figure out when this
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

        title = OBALoc("stop_problem_controller.title", value: "Report a Problem", comment: "Title for the Report Stop Problem controller")

        registerDefaults()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - User Defaults

    private func registerDefaults() {
        application.userDefaults.register(defaults: [
            UserDefaultKeys.shareLocation: true
        ])
    }

    private struct UserDefaultKeys {
        static let shareLocation = "shareLocationForStopProblemReporting"
    }

    private var isLocationSharingPermitted: Bool {
        get {
            application.userDefaults.bool(forKey: UserDefaultKeys.shareLocation)
        }
        set {
            application.userDefaults.set(newValue, forKey: UserDefaultKeys.shareLocation)
        }
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.reportProblem, value: "feedback_stop_problem")

        form
        // Problem Section
        +++ Section(OBALoc("stop_problem_controller.problem_section.section_title", value: "What seems to be the problem?", comment: "Title of the first section in the Stop Problem Controller."))
        <<< PickerInputRow<StopProblemCode>("stopProblemCode") {
            $0.title = OBALoc("stop_problem_controller.problem_section.row_label", value: "Pick one:", comment: "Title label for the 'choose a problem type' row.")

            $0.options = StopProblemCode.allCases
            $0.value = $0.options.first
            $0.displayValueFor = { code -> String? in
                guard let code = code else { return nil }
                return code.userFriendlyStringValue
            }
        }

        // Comments Section
        +++ Section(OBALoc("stop_problem_controller.comments_section.section_title", value: "Additional comments (optional)", comment: "The section header to a free-form comments field that the user does not have to add text to in order to submit this form."))
        <<< TextAreaRow(tag: "comments")

        // Share Location
        +++ Section(
            header: OBALoc("stop_problem_controller.location_section.section_title", value: "Share your location?", comment: "Title of the Share Location section in the Stop Problem Controller."),
            footer: OBALoc("stop_problem_controller.location_section.section_footer", value: "Sharing your location can help your transit agency fix this problem.", comment: "Footer text of the Share Location section in the Stop Problem Controller"))
        <<< shareLocationSwitch

        // Button Section
        +++ Section()
        <<< ButtonRow {
            $0.title = OBALoc("stop_problem_controller.send_button", value: "Send Message", comment: "The 'send' button that actually sends along the problem report.")
            $0.onCellSelection { [weak self] (_, _) in
                guard let self = self else { return }
                self.submitForm()
            }
        }
    }

    private lazy var shareLocationSwitch = SwitchRow {
        $0.title = OBALoc("stop_problem_controller.location_section.switch_title", value: "Share location", comment: "Title of the Share Location switch on stop problem controller")
        $0.value = self.isLocationSharingPermitted
        $0.onChange { [weak self] (r2) in
            guard
                let self = self,
                let value = r2.value
            else { return }

            self.isLocationSharingPermitted = value
        }
    }

    private func submitForm() {
        guard
            let codeRow = form.rowBy(tag: "stopProblemCode") as? PickerInputRow<StopProblemCode>,
            let commentRow = form.rowBy(tag: "comments") as? TextAreaRow,
            let stopProblemCode = codeRow.value,
            let apiService = application.restAPIService
        else { return }

        let location = isLocationSharingPermitted ? application.locationService.currentLocation : nil

        SVProgressHUD.show()

        let op = apiService.getStopProblem(stopID: stop.id, code: stopProblemCode, comment: commentRow.value, location: location)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                AlertPresenter.show(error: error, presentingController: self)
                SVProgressHUD.dismiss()
            case .success:
                self.application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.reportProblem, value: "Reported Stop Problem")
                SVProgressHUD.showSuccessAndDismiss()
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
}
