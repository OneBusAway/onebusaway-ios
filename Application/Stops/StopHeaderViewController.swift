//
//  StopHeaderViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/29/19.
//

import UIKit

/*
 background: map of area around stop
 - [Stop name]
 - [ Stop # - cardinal direction]
 - [Routes: list]
 */

/// This view controller is meant to embedded into a classic UI
/// `StopViewController` and used as the header view for that controller.
public class StopHeaderViewController: UIViewController {
    
    private let kHeaderHeight: CGFloat = 120.0
    
    private let backgroundImageView = UIImageView.autolayoutNew()
    private let stopNameLabel = UILabel.autolayoutNew()
    private let stopNumberLabel = UILabel.autolayoutNew()
    private let routesLabel = UILabel.autolayoutNew()
    
    private var snapshotter: MapSnapshotter?
    
    public init() {
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
        
        view.backgroundColor = .magenta
        
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
        stack.pinToSuperview(.layoutMargins)
        
        func buildStopInfoLabelText(from stopArrivals: StopArrivals) -> String {
            let fmt = NSLocalizedString("stop_controller.stop_info_label_fmt", value: "Stop #%@", comment: "Stop info - e.g. 'Stop #{12345}")
            if let adj = Formatters.adjectiveFormOfCardinalDirection(stopArrivals.stop.direction) {
                return [String(format: fmt, stopArrivals.stop.code), adj].joined(separator: " – ")
            }
            else {
                return String(format: fmt, stopArrivals.stop.code)
            }
        }
        
        // abxoxo
        // let stopInfoText = buildStopInfoLabelText(from: stopArrivals)
        // let routeText = Formatters.formattedRoutes(stopArrivals.stop.routes)
        // titleBar.subtitleLabel.text = "\(stopInfoText)\r\n\(routeText)"
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
        stopNumberLabel.text = "\(stop.code) - \(stop.direction)"
        routesLabel.text = Formatters.formattedRoutes(stop.routes)
    }
}
