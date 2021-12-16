//
//  CustomRegionBuilderController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/16/21.
//

import UIKit
import Eureka
import OBAKitCore
import MapKit

protocol RegionBuilderDelegate: AnyObject {
    func reloadRegions()
}

class CustomRegionBuilderController: FormViewController {

    // MARK: - Properties

    private let application: Application
    private let region: Region?

    public weak var delegate: RegionBuilderDelegate?

    // MARK: - Init

    init(application: Application, region: Region?, delegate: RegionBuilderDelegate?) {
        self.application = application
        self.region = region
        self.delegate = delegate

        super.init(style: .insetGrouped)

        if region == nil {
            title = OBALoc("custom_region_builder_controller.new_title", value: "Add Custom Region", comment: "Title for the region builder controller in add mode")
        }
        else {
            title = OBALoc("custom_region_builder_controller.edit_title", value: "Edit Custom Region", comment: "Title for the region builder controller in edit mode")
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Actions

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func save() {
        let values = form.values()

        guard
            let name = values[regionNameTag] as? String,
            let email = values[contactEmailTag] as? String,
            let baseURL = values[baseURLTag] as? URL,
            let mapRect = values[serviceRectTag] as? MKMapRect
        else {
            AlertPresenter.show(errorMessage: OBALoc("custom_region_builder_controller.save_validation_error", value: "Please fill out all fields", comment: "The error that is shown when the custom region builder does not have all of its fields filled in."), presentingController: self)
            return
        }

        let region = Region(name: name, OBABaseURL: baseURL, coordinateRegion: MKCoordinateRegion(mapRect), contactEmail: email, regionIdentifier: self.region?.regionIdentifier ?? nil)

        application.regionsService.addCustomRegion(region)
        application.regionsService.currentRegion = region

        self.delegate?.reloadRegions()

        dismiss(animated: true, completion: nil)
    }

    // MARK: - UIViewController

    override public func viewDidLoad() {
        super.viewDidLoad()
        form
            +++ regionNameSection
            +++ baseURLSection
            +++ contactEmailSection
            +++ serviceRectSection

        setFormValues()
    }

    // MARK: - Form Builder

    private let regionNameTag = "regionName"
    private let baseURLTag = "baseURL"
    private let serviceRectTag = "serviceRect"
    private let contactEmailTag = "contactEmail"

    private func setFormValues() {
        var values = [String: Any]()

        if let region = region {
            values[regionNameTag] = region.name
            values[baseURLTag] = region.OBABaseURL
            values[contactEmailTag] = region.contactEmail
            values[serviceRectTag] = region.serviceRect
        }
        else {
            values[regionNameTag] = OBALoc("custom_region_builder_controller.example_data.region_name", value: "My Custom Region", comment: "Example custom region name")
            values[baseURLTag] = URL(string: "https://api.tampa.onebusaway.org/api/")
            values[contactEmailTag] = "contact@example.com"
            values[serviceRectTag] = MKMapRect(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.9654987, longitude: -82.5101761), latitudinalMeters: 2000, longitudinalMeters: 2000))
        }

        form.setValues(values)
    }

    private lazy var regionNameSection: Section = {
        let title = OBALoc("custom_region_builder_controller.name_section.header_title", value: "Region Name", comment: "Title of the Region Name header.")
        let section = Section(title)
        section <<< TextRow {
            $0.tag = regionNameTag
        }

        return section
    }()

    private lazy var baseURLSection: Section = {
        let title = OBALoc("custom_region_builder_controller.base_url_section.header_title", value: "Base URL", comment: "Title of the Base URL header.")
        let section = Section(title)
        section <<< URLRow {
            $0.tag = baseURLTag
        }

        return section
    }()

    private lazy var contactEmailSection: Section = {
        let title = OBALoc("custom_region_builder_controller.contact_email_section.header_title", value: "Contact Email", comment: "Title of the Contact Email header.")
        let section = Section(title)
        section <<< EmailRow {
            $0.tag = contactEmailTag
        }

        return section
    }()

    private lazy var serviceRectSection: Section = {
        let title = OBALoc("custom_region_builder_controller.service_area_section.header_title", value: "Service Area", comment: "Title of the Service Area header.")
        let section = Section(title)
        section <<< MapRectRow {
            $0.tag = serviceRectTag
        }

        return section
    }()
}
