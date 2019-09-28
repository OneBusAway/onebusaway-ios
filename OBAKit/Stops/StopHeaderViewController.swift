//
//  StopHeaderViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/29/19.
//

import UIKit
import OBAKitCore

/// This view controller is meant to embedded into a classic UI
/// `StopViewController` and used as the header view for that controller.
public class StopHeaderViewController: UIViewController {
    private let kHeaderHeight: CGFloat = 120.0

    private let backgroundImageView = UIImageView.autolayoutNew()
    private lazy var stopNameLabel = buildLabel(bold: true)
    private lazy var stopNumberLabel = buildLabel()
    private lazy var routesLabel = buildLabel(bold: false, numberOfLines: 0)

    private var snapshotter: MapSnapshotter?

    private let application: Application

    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public var stop: Stop? {
        didSet {
            updateUI()
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.mapSnapshotOverlayColor

        view.addSubview(backgroundImageView)
        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundImageView.heightAnchor.constraint(equalToConstant: kHeaderHeight)
        ])

        let stack = UIStackView.verticalStack(arangedSubviews: [stopNameLabel, stopNumberLabel, routesLabel, UIView.autolayoutNew()])
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: ThemeMetrics.padding),
            stack.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
        ])
    }

    private func updateUI() {
        guard let stop = stop else { return }

        let size = CGSize(width: UIScreen.main.bounds.width, height: kHeaderHeight)
        snapshotter = MapSnapshotter(size: size, stopIconFactory: application.stopIconFactory)

        snapshotter?.snapshot(stop: stop, traitCollection: traitCollection) { [weak self] image in
            guard let self = self else { return }
            self.backgroundImageView.image = image
        }

        stopNameLabel.text = stop.name
        stopNumberLabel.text = Formatters.formattedCodeAndDirection(stop: stop)
        routesLabel.text = Formatters.formattedRoutes(stop.routes)
    }

    private func buildLabel(bold: Bool = false, numberOfLines: Int = 1) -> UILabel {
        let label = UILabel.autolayoutNew()
        label.textColor = .white
        label.shadowColor = .black
        label.numberOfLines = numberOfLines
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.font = bold ? UIFont.preferredFont(forTextStyle: .body).bold : UIFont.preferredFont(forTextStyle: .body)
        return label
    }
}
