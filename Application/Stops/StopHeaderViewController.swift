//
//  StopHeaderViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/29/19.
//

import UIKit

/// This view controller is meant to embedded into a classic UI
/// `StopViewController` and used as the header view for that controller.
public class StopHeaderViewController: UIViewController {

    private let kHeaderHeight: CGFloat = 120.0

    private let backgroundImageView = UIImageView.autolayoutNew()
    private lazy var stopNameLabel = buildLabel(bold: true)
    private lazy var stopNumberLabel = buildLabel()
    private lazy var routesLabel = buildLabel()

    private var snapshotter: MapSnapshotter?

    private let application: Application

    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        snapshotter?.cancel()
    }

    public var stop: Stop? {
        didSet {
            updateUI()
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = MapSnapshotter.defaultOverlayColor

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

        stack.pinToSuperview(.layoutMargins, insets: NSDirectionalEdgeInsets(top: ThemeMetrics.padding, leading: 0, bottom: 0, trailing: 0))
    }

    private func updateUI() {
        guard let stop = stop else { return }

        snapshotter?.cancel()
        snapshotter = nil

        let size = CGSize(width: UIScreen.main.bounds.width, height: kHeaderHeight)
        snapshotter = MapSnapshotter(size: size, coordinate: stop.coordinate)

        snapshotter?.snapshot(stop: stop) { [weak self] image in
            guard let self = self else { return }

            self.backgroundImageView.image = image
        }

        stopNameLabel.text = stop.name
        stopNumberLabel.text = Formatters.formattedCodeAndDirection(stop: stop)
        routesLabel.text = Formatters.formattedRoutes(stop.routes)
    }

    private func buildLabel(bold: Bool = false) -> UILabel {
        let label = UILabel.autolayoutNew()
        label.textColor = .white
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.font = bold ? UIFont.preferredFont(forTextStyle: .body).bold : UIFont.preferredFont(forTextStyle: .body)
        return label
    }
}
