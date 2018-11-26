//
//  PermissionPromptViewController.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBALocationKit

@objc(OBAPermissionPromptViewController)
public class PermissionPromptViewController: UIViewController {

    private let application: Application

    private var locationService: LocationService {
        return application.locationService
    }

    public lazy var topImageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "header", in: Bundle(for: PermissionPromptViewController.self), compatibleWith: nil)
        imageView.heightAnchor.constraint(equalToConstant: 100.0).isActive = true

        imageView.backgroundColor = application.theme.colors.primary

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

    @objc public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("permission_prompt_controller.title", value: "Welcome", comment: "View controller title in the permission prompt controller.")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        let imageViewWrapper = topImageView.embedInWrapperView(setConstraints: false)
        topImageView.leadingAnchor.pin(to: imageViewWrapper.leadingAnchor)
        topImageView.trailingAnchor.pin(to: imageViewWrapper.trailingAnchor)
        topImageView.centerYAnchor.pin(to: imageViewWrapper.centerYAnchor)

        let stack = UIStackView.oba_verticalStack(arangedSubviews: [topImageView, textView])
        view.addSubview(stack)

        stack.pinEdgesToSuperview()
    }
}
