//
//  RegionCustomForm.swift
//  OBAKit
//
//  Created by Alan Chu on 1/20/23.
//

import MapKit
import SwiftUI
import OBAKitCore
import CoreLocationUI

/// Create (or edit) a custom region.
struct RegionCustomForm: View {
    @Environment(\.dismiss) var dismiss
    var regionProvider: any RegionProvider

    public var existingRegion: Region?

    // MARK: Form Fields
    @State private var regionName: String = ""
    @State private var baseURLString: String = ""
    @State private var contactEmail: String = ""
    @State private var serviceArea: MKMapRect = MKMapRect(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.9654987, longitude: -82.5101761), latitudinalMeters: 2000, longitudinalMeters: 2000))

    var validateForm: Bool {
        return
            !regionName.isEmpty &&
            !contactEmail.isEmpty &&
            URL(string: baseURLString) != nil
    }

    // MARK: Other Form state

    @State private var disableForm: Bool = false
    @State private var error: Error?

    var navigationTitle: String {
        if existingRegion == nil {
            return OBALoc("custom_region_builder_controller.new_title", value: "Add Custom Region", comment: "Title for the region builder controller in add mode")
        } else {
            return OBALoc("custom_region_builder_controller.edit_title", value: "Edit Custom Region", comment: "Title for the region builder controller in edit mode")
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(OBALoc("custom_region_builder_controller.name_section.header_title", value: "Region Name", comment: "Title of the Region Name header.")) {
                    TextField(OBALoc("custom_region_builder_controller.example_data.region_name", value: "My Custom Region", comment: "Example custom region name"), text: $regionName)
                }

                Section(OBALoc("custom_region_builder_controller.base_url_section.header_title", value: "Base URL", comment: "Title of the Base URL header.")) {
                    TextField("https://api.tampa.onebusaway.org/api/", text: $baseURLString)
                        .textContentType(.URL)
                }

                Section(OBALoc("custom_region_builder_controller.contact_email_section.header_title", value: "Contact Email", comment: "Title of the Contact Email header.")) {
                    TextField("contact@example.com", text: $contactEmail)
                        .textContentType(.emailAddress)
                }

                Section {
                    ZStack {
                        Map(mapRect: $serviceArea)

                        // Add a outlined border to indicate to the user that they
                        // are picking a service "rectangle" on the map.
                        Rectangle()
                            .fill(.clear)
                            .border(.selection, width: 7)
                            .shadow(color: .gray, radius: 5)
                            .frame(width: 270, height: 250)
                            .allowsHitTesting(false)
                    }
                    .frame(minHeight: 300)
                } header: {
                    Text(OBALoc("custom_region_builder_controller.service_area_section.header_title", value: "Service Area", comment: "Title of the Service Area header."))
                } footer: {
                    Text(OBALoc("custom_region_builder_controller.service_area_section.explanation", value: "Drag the map to the approximate service area of this region.", comment: "An explanation of dragging the map to highlight the service area of a custom region."))
                }
            }
            .errorAlert(error: $error)
            .onAppear(perform: setInitialValues)
            .disabled(disableForm)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
                    TaskButton(Strings.save, actionOptions: [.disableButton], action: doSave)
                        .disabled(validateForm == false)
                }

                ToolbarItemGroup(placement: .cancellationAction) {
                    Button(Strings.cancel) {
                        print()
                    }
                }
            }
        }
    }

    func setInitialValues() {
        guard let existingRegion else {
            return
        }

        regionName = existingRegion.name
        baseURLString = existingRegion.OBABaseURL.path
        contactEmail = existingRegion.contactEmail
        serviceArea = existingRegion.serviceRect
    }

    @Sendable
    func doSave() async {
        guard !disableForm, let baseURL = URL(string: baseURLString) else {
            return
        }

        disableForm = true
        defer {
            disableForm = false
        }

        let region = Region(
            name: regionName,
            OBABaseURL: baseURL,
            coordinateRegion: MKCoordinateRegion(serviceArea),
            contactEmail: contactEmail,
            regionIdentifier: existingRegion?.regionIdentifier
        )

        do {
            try await regionProvider.add(customRegion: region)
            self.error = nil
        } catch {
            self.error = error
        }
    }
}

struct RegionCustomForm_Previews: PreviewProvider {
    static var previews: some View {
        RegionCustomForm(regionProvider: Previews_SampleRegionProvider(), existingRegion: nil)
            .previewDisplayName("Add new region")

        RegionCustomForm(
            regionProvider: Previews_SampleRegionProvider(),
            existingRegion: .regionForPreview(id: 1, name: "Puget Sound", latitude: 47.59820, longitude: -122.32165, latitudeSpan: 0.33704, longitudeSpan: 0.440483)
        )
        .previewDisplayName("Edit existing region")
    }
}
