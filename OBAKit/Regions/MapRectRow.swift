//
//  MapRectRow.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/16/21.
//

import UIKit
import MapKit
import Eureka

extension MKMapRect: Equatable {
    public static func == (lhs: MKMapRect, rhs: MKMapRect) -> Bool {
        return
            lhs.origin.coordinate.distance(from: rhs.origin.coordinate) < 1.0 &&
            Int(lhs.size.height) == Int(rhs.size.height) &&
            Int(lhs.size.width) == Int(rhs.size.width)
    }
}

public final class MapRectRow: OptionsRow<PushSelectorCell<MKMapRect>>, PresenterRowType, RowType {
    public typealias PresentedControllerType = EurekaMapViewController
    public typealias PresenterRow = EurekaMapViewController

    /// Defines how the view controller will be presented, pushed, etc.
    public var presentationMode: PresentationMode<PresenterRow>?

    /// Will be called before the presentation occurs.
    public var onPresentCallback: ((FormViewController, PresenterRow) -> Void)?

    public required init(tag: String?) {
        super.init(tag: tag)
        presentationMode = .show(controllerProvider: ControllerProvider.callback {
            return EurekaMapViewController(nil)
        }, onDismiss: { vc in
            _ = vc.navigationController?.popViewController(animated: true)
        })

        displayValueFor = {
            guard let location = $0 else { return "" }
            return  "\(MKStringFromMapRect(location))"
        }
    }

    /**
     Extends `didSelect` method
     */
    public override func customDidSelect() {
        super.customDidSelect()
        guard let presentationMode = presentationMode, !isDisabled else { return }
        if let controller = presentationMode.makeController() {
            controller.row = self
            controller.title = selectorTitle ?? controller.title
            onPresentCallback?(cell.formViewController()!, controller)
            presentationMode.present(controller, row: self, presentingController: self.cell.formViewController()!)
        } else {
            presentationMode.present(nil, row: self, presentingController: self.cell.formViewController()!)
        }
    }

    /**
     Prepares the pushed row setting its title and completion callback.
     */
    public override func prepare(for segue: UIStoryboardSegue) {
        super.prepare(for: segue)
        guard let rowVC = segue.destination as? PresenterRow else { return }
        rowVC.title = selectorTitle ?? rowVC.title
        rowVC.onDismissCallback = presentationMode?.onDismissCallback ?? rowVC.onDismissCallback
        onPresentCallback?(cell.formViewController()!, rowVC)
        rowVC.row = self
    }
}

public class EurekaMapViewController: UIViewController, TypedRowControllerType, MKMapViewDelegate {

    public var row: RowOf<MKMapRect>!
    public var onDismissCallback: ((UIViewController) -> Void)?

    lazy var mapView: MKMapView = { [unowned self] in
        let v = MKMapView(frame: self.view.bounds)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return v
    }()

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    convenience public init(_ callback: ((UIViewController) -> Void)?) {
        self.init(nibName: nil, bundle: nil)
        onDismissCallback = callback
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(mapView)

        mapView.delegate = self

        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(EurekaMapViewController.tappedDone(_:)))
        navigationItem.rightBarButtonItem = button

        if let value = row.value {
            mapView.setVisibleMapRect(value, animated: true)
        }

        updateTitle()

    }

    @objc func tappedDone(_ sender: UIBarButtonItem) {
        row.value = mapView.visibleMapRect
        onDismissCallback?(self)
    }

    func updateTitle() {
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 4
        fmt.minimumFractionDigits = 4
        let latitude = fmt.string(from: NSNumber(value: mapView.centerCoordinate.latitude))!
        let longitude = fmt.string(from: NSNumber(value: mapView.centerCoordinate.longitude))!
        title = "\(latitude), \(longitude)"
    }

    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        updateTitle()
    }
}
