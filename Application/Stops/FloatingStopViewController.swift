//
//  FloatingStopViewController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 11/29/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import AloeStackView
import FloatingPanel

class FloatingStopViewController: VisualEffectViewController, FloatingPanelContent {
    private let kUseDebugColors = false

    public lazy var stackView: AloeStackView = {
        let stack = AloeStackView()
        stack.backgroundColor = .clear
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.rowInset = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        stack.showsVerticalScrollIndicator = false

        return stack
    }()

    let application: Application
    let stopID: String
    weak var delegate: FloatingPanelContainer?

    let minutesBefore: UInt = 5
    var minutesAfter: UInt = 35

    // MARK: Top Content

    private let titleBar = FloatingPanelTitleView.autolayoutNew()

    // MARK: - Bottom Content

    private lazy var loadMoreButton: UIButton = {
        let loadMoreButton = UIButton(type: .system)
        loadMoreButton.setTitle(NSLocalizedString("stop_controller.load_more_button", value: "Load More", comment: "Load More button"), for: .normal)
        loadMoreButton.addTarget(self, action: #selector(loadMore), for: .touchUpInside)
        return loadMoreButton
    }()

    // MARK: - Data

    var operation: StopArrivalsModelOperation?

    var stopArrivals: StopArrivals? {
        didSet {
            dataWillReload()

            if stopArrivals != nil {
                dataDidReload()
            }
        }
    }

    init(application: Application, stopID: String, delegate: FloatingPanelContainer?) {
        self.application = application
        self.stopID = stopID
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        toolbarItems = buildToolbarItems()
    }

    private func buildToolbarItems() -> [UIBarButtonItem] {
        let refreshButton = UIBarButtonItem(title: Strings.refresh, style: .plain, target: self, action: #selector(refresh))
        refreshButton.image = Icons.refresh

        let bookmarkButton = UIBarButtonItem(title: Strings.bookmark, style: .plain, target: self, action: #selector(addBookmark))
        bookmarkButton.image = Icons.favorited

        let filterButton = UIBarButtonItem(title: Strings.filter, style: .plain, target: self, action: #selector(filter))
        filterButton.image = Icons.filter

        return [filterButton, bookmarkButton, refreshButton]
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        operation?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if kUseDebugColors {
            titleBar.backgroundColor = .magenta
            titleBar.closeButton.backgroundColor = .purple
            titleBar.titleLabel.backgroundColor = .green
            titleBar.subtitleLabel.backgroundColor = .red
            stackView.backgroundColor = .yellow
        }

        titleBar.closeButton.addTarget(self, action: #selector(closePanel), for: .touchUpInside)

        let outerStack = UIStackView.verticalStack(arangedSubviews: [titleBar, stackView])
        outerStack.directionalLayoutMargins = application.theme.metrics.collectionViewLayoutMargins
        outerStack.isLayoutMarginsRelativeArrangement = true
        visualEffectView.contentView.addSubview(outerStack)

        let pinTargets = DirectionalPinTargets(leadingTrailing: .edges, topBottom: .edges)
        outerStack.pinToSuperview(pinTargets, insets: FloatingPanelSurfaceView.defaultTopEdgeInsets)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateData()
    }

    func updateData() {
        operation?.cancel()

        guard let modelService = application.restAPIModelService else {
            return
        }

        surfaceView()?.showProgressBar()

        let op = modelService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        op.then { [weak self] in
            guard let self = self else {
                return
            }

            self.stopArrivals = op.stopArrivals
            self.surfaceView()?.hideProgressBar()
        }

        self.operation = op
    }

    /// Call this method when data is about to reloaded in this controller
    func dataWillReload() {
        stackView.removeAllRows()
    }

    /// Call this method after data has been reloaded in this controller
    func dataDidReload() {
        guard let stopArrivals = stopArrivals else {
            return
        }

        application.userDataStore.addRecentStop(stopArrivals.stop)

        titleBar.titleLabel.text = stopArrivals.stop.name

        func buildStopInfoLabelText(from stopArrivals: StopArrivals) -> String {
            let fmt = NSLocalizedString("stop_controller.stop_info_label_fmt", value: "Stop #%@", comment: "Stop info - e.g. 'Stop #{12345}")
            if let adj = Formatters.adjectiveFormOfCardinalDirection(stopArrivals.stop.direction) {
                return [String(format: fmt, stopArrivals.stop.code), adj].joined(separator: " – ")
            }
            else {
                return String(format: fmt, stopArrivals.stop.code)
            }
        }

        let stopInfoText = buildStopInfoLabelText(from: stopArrivals)
        let routeText = Formatters.formattedRoutes(stopArrivals.stop.routes)
        titleBar.subtitleLabel.text = "\(stopInfoText)\r\n\(routeText)"

        for stopModel in stopArrivals.arrivalsAndDepartures.toVehicleStopModels() {
            var arrivalViews = [StopArrivalView]()
            for arrDep in stopModel.arrivalDepartures {
                let a = StopArrivalView.autolayoutNew()
                stackView.addRow(a, hideSeparator: true)
                a.arrivalDeparture = arrDep
                arrivalViews.append(a)
            }
            if let last = arrivalViews.last {
                stackView.showSeparator(forRow: last)
            }
        }

        stackView.addRow(loadMoreButton, hideSeparator: true)
    }

    // MARK: - FloatingPanelContainer

    public var bottomScrollInset: CGFloat {
        get {
            return stackView.contentInset.bottom
        }
        set {
            stackView.contentInset.bottom = newValue
        }
    }
}

// MARK: - Actions
extension FloatingStopViewController {
    @objc private func closePanel() {
        delegate?.closePanel(containing: self, model: stopArrivals?.stop)
    }

    @objc private func refresh() {
        updateData()
    }

    @objc private func addBookmark() {

    }

    @objc private func filter() {

    }

    @objc private func loadMore() {
        self.minutesAfter += 30
        updateData()
    }
}
