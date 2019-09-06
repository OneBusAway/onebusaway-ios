//
//  AlarmBuilderViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/4/19.
//

import UIKit

// abxoxo - todo - build this out.

class AlarmBuilderViewController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {

    // MARK: - Debugging

    private let kUseDebugColors = false

    // MARK: - App State and Data

    private let application: Application
    private let arrivalDeparture: ArrivalDeparture
    public weak var delegate: ModalDelegate?

    // MARK: - Picker

    private let pickerItems: [Int]

    private lazy var timePicker: UIPickerView = {
        let picker = UIPickerView(frame: .zero)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.delegate = self
        picker.dataSource = self
        return picker
    }()

    // MARK: - Other UI

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel.autolayoutNew()
         titleLabel.font = UIFont.preferredFont(forTextStyle: .title2).bold
         titleLabel.numberOfLines = 0
         titleLabel.text = NSLocalizedString("alarm_builder_controller.remind_me_label", value: "Remind me before departure", comment: "A label that sits at the top of the alarm builder controller.")

        return titleLabel
    }()

    private lazy var cancelButton = buildButton(title: Strings.cancel, action: #selector(cancel))
    private lazy var saveButton = buildButton(title: Strings.save, action: #selector(save))
    private lazy var buttonStack: UIStackView = {
        let buttonStack = UIStackView.horizontalStack(arrangedSubviews: [cancelButton, saveButton])
        buttonStack.alignment = .center
        buttonStack.distribution = .fillEqually
        return buttonStack
    }()
    private lazy var buttonWrapper = buttonStack.embedInWrapperView()
    private lazy var outerStack = UIStackView.verticalStack(arangedSubviews: [titleLabel, timePicker, buttonWrapper])

    // MARK: - Init

    init(application: Application, arrivalDeparture: ArrivalDeparture, delegate: ModalDelegate?) {
        self.application = application
        self.arrivalDeparture = arrivalDeparture
        self.pickerItems = AlarmBuilderViewController.incrementsForDeparture(arrivalDeparture.arrivalDepartureMinutes)
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        let selectedRow = pickerItems.count >= 10 ? 9 : pickerItems.count - 1
        timePicker.selectRow(selectedRow, inComponent: 0, animated: false)

        view.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: ThemeMetrics.floatingPanelTopInset),
            outerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            outerStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])

        if kUseDebugColors {
            cancelButton.backgroundColor = .green
            saveButton.backgroundColor = .red
            timePicker.backgroundColor = .yellow
            buttonWrapper.backgroundColor = .blue
        }
    }

    // MARK: - Actions

    @objc private func cancel() {
        delegate?.dismissModalController(self)
    }

    @objc private func save() {
        //
    }

    // MARK: - Picker Data Source

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { pickerItems.count }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let minutes = pickerItems[row]
        if minutes == 1 {
            return NSLocalizedString("alarm_builder_controller.one_minute", value: "1 minute", comment: "One minute/1 minute")
        }
        else {
            let fmt = NSLocalizedString("alarm_builder_controller.minutes_fmt", value: "%d minutes", comment: "{X} minutes. always plural.")
            return String(format: fmt, minutes)
        }
    }

    // MARK: - Private Helpers

    /// Creates an array of `Int`s representing the countdown of minutes that will be displayed in this controller's picker.
    /// - Parameter minutes: Total minutes until departure.
    private class func incrementsForDeparture(_ minutes: Int) -> [Int] {
        var increments = [Int]()

        var cursor = 1

        while cursor < minutes {
            increments.append(cursor)

            if cursor < 10 {
                cursor += 1
            }
            else if cursor < 30 {
                cursor += 5
            }
            else if cursor < 120 {
                cursor += 15
            }
            else {
                cursor += 30
            }
        }

        return increments.reversed()
    }

    /// Builds an OK or Cancel button for this controller.
    /// - Parameter title: Button title
    /// - Parameter action: The selector for the button. Targets `self`
    private func buildButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body).bold
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0).isActive = true

        return button
    }
}
