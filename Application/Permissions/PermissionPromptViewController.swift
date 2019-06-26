//
//  PermissionPromptViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

/// A modal view controller that tells the user a little bit about OneBusAway and prompts them to allow access to their location.
@objc(OBAPermissionPromptViewController)
public class PermissionPromptViewController: UIViewController {

    private let kUseDebugColors = false

    private let application: Application

    private var locationService: LocationService {
        return application.locationService
    }

    public lazy var topImageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = Icons.header
        imageView.backgroundColor = application.theme.colors.primary
        imageView.heightAnchor.constraint(equalToConstant: 100.0).isActive = true

        return imageView
    }()

    public lazy var textView: UITextView = {
        let textView = UITextView(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isSelectable = false
        textView.isEditable = false
        textView.font = application.theme.fonts.body

        textView.text = NSLocalizedString("permission_prompt_controller.explanation", value: "OneBusAway is an open source, volunteer-run app that helps you find out where your buses, trains, ferries, and more are in real time.\r\n\r\nThe app works best when it can find your location.\r\n\r\nPlease tap the button below to get started.", comment: "Explanation text in the permission prompt controller that appears when the app first launches.")

        return textView
    }()

    public lazy var grantPermissionsButton: UIButton = {
        let button = BorderedButton.autolayoutNew()
        button.addTarget(self, action: #selector(requestLocationPermission), for: .touchUpInside)

        let title = NSLocalizedString("permission_prompt_controller.grant_permissions_button_title", value: "Allow Location Access", comment: "Button title for authorizing location use.")
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0).isActive = true

        return button
    }()

    // MARK: - Initialization

    @objc public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("permission_prompt_controller.title", value: "Welcome", comment: "View controller title in the permission prompt controller.")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = application.theme.colors.systemBackground

        let imageViewWrapper = topImageView.embedInWrapperView(setConstraints: false)
        imageViewWrapper.backgroundColor = topImageView.backgroundColor

        NSLayoutConstraint.activate([
            topImageView.topAnchor.constraint(equalTo: imageViewWrapper.topAnchor, constant: ThemeMetrics.padding),
            topImageView.bottomAnchor.constraint(equalTo: imageViewWrapper.bottomAnchor, constant: -ThemeMetrics.padding),
            topImageView.leadingAnchor.constraint(equalTo: imageViewWrapper.leadingAnchor, constant: 0),
            topImageView.trailingAnchor.constraint(equalTo: imageViewWrapper.trailingAnchor, constant: 0)
        ])

        let buttonWrapper = grantPermissionsButton.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            grantPermissionsButton.topAnchor.constraint(equalTo: buttonWrapper.topAnchor, constant: ThemeMetrics.padding),
            grantPermissionsButton.bottomAnchor.constraint(equalTo: buttonWrapper.bottomAnchor, constant: -ThemeMetrics.padding),
            grantPermissionsButton.centerXAnchor.constraint(equalTo: buttonWrapper.centerXAnchor),
            buttonWrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: 60.0)
        ])

        let stack = UIStackView.verticalStack(arangedSubviews: [imageViewWrapper, textView, buttonWrapper])
        view.addSubview(stack)

        stack.pinToSuperview(.safeArea)

        if kUseDebugColors {
            imageViewWrapper.backgroundColor = .brown
            grantPermissionsButton.backgroundColor = .green
            textView.backgroundColor = .red
            topImageView.backgroundColor = .magenta
        }
    }

    // MARK: - Actions

    @objc func requestLocationPermission() {
        application.locationService.requestInUseAuthorization()
    }
}
