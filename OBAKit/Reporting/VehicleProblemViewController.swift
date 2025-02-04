//
//  VehicleProblemViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Eureka
import OBAKitCore

// This seems...busted. I can't figure out when this
// initializer will actually be called, though. Do I even
// really need it?
extension TripProblemCode: @retroactive InputTypeInitiable {
    public init?(string stringValue: String) {
        return nil
    }
}

class VehicleProblemViewController: FormViewController {
    // MARK: - Properties
    private let application: Application
    private let arrivalDeparture: ArrivalDeparture

    // MARK: - Form Rows

    private lazy var problemCodePicker: PickerInputRow<TripProblemCode> = {
        return PickerInputRow<TripProblemCode> {
            $0.title = OBALoc("vehicle_problem_controller.problem_section.row_label", value: "Pick one", comment: "Title label for the 'choose a problem type' row.")
            $0.options = TripProblemCode.allCases
            $0.value = $0.options.first
            $0.displayValueFor = { code -> String? in
                guard let code = code else { return nil }
                return code.userFriendlyStringValue
            }
        }
    }()

    private lazy var onVehicleSwitch = SwitchRow {
        $0.title = OBALoc("vehicle_problem_controller.on_vehicle_section.switch_title", value: "On the vehicle", comment: "Title of the 'on the vehicle' switch in the Vehicle Problem Controller.")
    }

    private lazy var vehicleIDField = TextRow {
        $0.title = OBALoc("vehicle_problem_controller.on_vehicle_section.vehicle_id_title", value: "Vehicle ID", comment: "Title of the vehicle ID text field in the Vehicle Problem Controller.")

        $0.value = arrivalDeparture.vehicleID
    }

    private lazy var shareLocationSwitch = SwitchRow {
        $0.title = OBALoc("vehicle_problem_controller.location_section.switch_title", value: "Share location", comment: "Title of the Share Location switch")
        $0.value = self.isLocationSharingPermitted
        $0.onChange { [weak self] (r2) in
            guard
                let self = self,
                let value = r2.value
            else { return }

            self.isLocationSharingPermitted = value
        }
    }

    private lazy var commentsField = TextAreaRow()

    // MARK: - Init

    init(application: Application, arrivalDeparture: ArrivalDeparture) {
        self.application = application
        self.arrivalDeparture = arrivalDeparture

        super.init(style: .insetGrouped)

        title = OBALoc("vehicle_problem_controller.title", value: "Report a Problem", comment: "Title for the Report Vehicle Problem controller")

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
        static let shareLocation = "VehicleProblemViewController.shareLocationForVehicleProblemReporting"
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

        application.analytics?.reportEvent(pageURL: "app://localhost/vehicle-problem", label: AnalyticsLabels.reportProblem, value: "feedback_trip_problem")

        let commentsRow = TextAreaRow()

        form

        // Trip Problem Code
        +++ Section(OBALoc("vehicle_problem_controller.problem_section.section_title", value: "What seems to be the problem?", comment: "Title of the first section in the Vehicle Problem Controller."))
        <<< problemCodePicker

        // On the Vehicle
        +++ Section(OBALoc("vehicle_problem_controller.on_vehicle_section.section_title", value: "Are you on this vehicle?", comment: "Title of the 'on the vehicle' section in the Vehicle Problem Controller."))
        <<< onVehicleSwitch
        <<< vehicleIDField

        // Share Location
        +++ Section(
            header: OBALoc("vehicle_problem_controller.location_section.section_title", value: "Share your location?", comment: "Title of the Share Location section in the Vehicle Problem Controller."),
            footer: OBALoc("vehicle_problem_controller.location_section.section_footer", value: "Sharing your location can help your transit agency fix this problem.", comment: "Footer text of the Share Location section in the Vehicle Problem Controller"))
        <<< shareLocationSwitch

        // Comments Section
        +++ Section(OBALoc("vehicle_problem_controller.comments_section.section_title", value: "Additional comments (optional)", comment: "The section header to a free-form comments field that the user does not have to add text to in order to submit this form."))
        <<< commentsRow

            // Button Section
        +++ Section()
        <<< ButtonRow {
            $0.title = OBALoc("vehicle_problem_controller.send_button", value: "Send Message", comment: "The 'send' button that actually sends along the problem report.")
            $0.onCellSelection { [weak self] (_, _) in
                guard let self = self else { return }
                Task {
                    await self.submitForm()
                }
            }
        }
    }

    private func submitForm() async {
        guard
            let apiService = application.apiService,
            let tripProblemCode = problemCodePicker.value
        else { return }

        let onVehicle = onVehicleSwitch.value ?? false
        let location = isLocationSharingPermitted ? application.locationService.currentLocation : nil

        let report = RESTAPIService.TripProblemReport(
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: vehicleIDField.value,
            stopID: arrivalDeparture.stopID,
            code: tripProblemCode,
            comment: commentsField.value,
            userOnVehicle: onVehicle,
            location: location
        )

        await MainActor.run {
            ProgressHUD.show()
        }

        do {
            _ = try await apiService.getTripProblem(report: report)
            self.application.analytics?.reportEvent(pageURL: "app://localhost/vehicle-problem", label: AnalyticsLabels.reportProblem, value: "Reported Trip Problem")

            await MainActor.run {
                ProgressHUD.showSuccessAndDismiss()
                self.dismiss(animated: true, completion: nil)
            }
        } catch {
            await MainActor.run {
                ProgressHUD.dismiss()
            }
            await AlertPresenter.show(error: error, presentingController: self)
        }
    }
}
