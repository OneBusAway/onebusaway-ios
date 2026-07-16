//
//  RegionCustomForm.swift
//  OBAKit
//
//  Created by Alan Chu on 1/20/23.
//

import MapKit
import SwiftUI
import OBAKitCore

/// Create (or edit) a custom region.
struct RegionCustomForm: View {
    @Environment(\.dismiss) var dismiss
    var regionProvider: any RegionProvider

    @Binding public var editingRegion: Region?

    private static let defaultRegionName = OBALoc("custom_region_builder_controller.example_data.region_name", value: "My Custom Region", comment: "Example custom region name")

    /// The contact email is not user-facing anymore; custom regions get a placeholder value.
    private static let placeholderContactEmail = "example@example.com"

    // MARK: Form Fields
    @State private var regionName: String = ""
    @State private var baseURLString: String = ""
    @State private var serviceArea: MKMapRect = MKMapRect(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.9654987, longitude: -82.5101761), latitudinalMeters: 2000, longitudinalMeters: 2000))
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// The Base URL field, normalized into an URL. `https://` is assumed if the user didn't type a scheme.
    var normalizedBaseURL: URL? {
        Self.normalizeBaseURL(baseURLString)
    }

    /// Normalizes user input into a base URL: trims whitespace, assumes
    /// `https://` when no scheme was typed, and strips a trailing `/api/where`
    /// (the field's help text promises that part is added automatically, so
    /// pasting a full API URL must not double it). Static and pure for
    /// testability.
    static func normalizeBaseURL(_ string: String) -> URL? {
        var urlString = string.strip()
        guard !urlString.isEmpty else {
            return nil
        }

        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        while urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        if urlString.lowercased().hasSuffix("/api/where") {
            urlString = String(urlString.dropLast("/api/where".count))
        }

        guard
            let url = URL(string: urlString),
            let scheme = url.scheme,
            scheme == "http" || scheme == "https",
            url.host() != nil
        else {
            return nil
        }

        return url
    }

    var validateForm: Bool {
        return normalizedBaseURL != nil
    }

    // MARK: Other Form state

    @State private var disableForm: Bool = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var error: Error?

    var body: some View {
        Form {
            Section {
                TextField(Self.defaultRegionName, text: $regionName)
            } header: {
                Text(OBALoc("custom_region_builder_controller.name_section.header_title", value: "Name", comment: "Title of the Name header."))
            } footer: {
                Text(OBALoc("custom_region_builder_controller.name_section.explanation", value: "Optional. If you leave this blank, the region will be named after its first transit agency.", comment: "An explanation of the optional custom region name field."))
            }

            Section {
                TextField("api.tampa.onebusaway.org", text: $baseURLString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(OBALoc("custom_region_builder_controller.base_url_section.header_title", value: "Base URL", comment: "Title of the Base URL header."))
            } footer: {
                Text(OBALoc("custom_region_builder_controller.base_url_section.explanation", value: "The root address of the region's API server, without the \"/api/where\" part—that gets added automatically. \"https://\" is assumed.", comment: "An explanation of what the Base URL field of a custom region requires."))
            }

            Section {
                ZStack {
                    Map(position: $cameraPosition)
                        .onMapCameraChange(frequency: .onEnd) { context in
                            serviceArea = context.rect
                        }

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

            if editingRegion != nil {
                Section {
                    Button(role: .destructive) {
                        isPresentingDeleteConfirmation = true
                    } label: {
                        Label(Strings.delete, systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(regionProvider.currentRegion == editingRegion)
                }
            }
        }
        .navigationTitle(editingRegion == nil
            ? OBALoc("custom_region_builder_controller.new_title", value: "New Custom Region", comment: "Navigation bar title when creating a new custom region.")
            : OBALoc("custom_region_builder_controller.edit_title", value: "Edit Custom Region", comment: "Navigation bar title when editing an existing custom region."))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Strings.confirmDelete, isPresented: $isPresentingDeleteConfirmation) {
            Button(Strings.delete, role: .destructive, action: doDelete)
        }
        .errorAlert(error: $error)
        .onAppear(perform: setInitialValues)
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                TaskButton(Strings.save, actionOptions: [.disableButton], action: doSave)
                    .disabled(validateForm == false)
            }

            ToolbarItemGroup(placement: .cancellationAction) {
                Button(Strings.cancel) {
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled()
        .navigationBarBackButtonHidden(true)
        .disabled(disableForm)
    }

    func setInitialValues() {
        if let editingRegion {
            regionName = editingRegion.name
            baseURLString = displayString(for: editingRegion.OBABaseURL)
            serviceArea = editingRegion.serviceRect
        }
        else if let location = regionProvider.currentLocation {
            serviceArea = MKMapRect(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000))
        }
        cameraPosition = .rect(serviceArea)
    }

    /// Strips the assumed `https://` scheme for display in the Base URL field.
    private func displayString(for url: URL) -> String {
        let urlString = url.absoluteString
        if urlString.hasPrefix("https://") {
            return String(urlString.dropFirst("https://".count))
        }
        return urlString
    }

    // @MainActor because these mutate @State (`disableForm`, `error`);
    // publishing SwiftUI state off the main actor is undefined behavior.
    @MainActor
    func doDelete() {
        Task {
            guard !disableForm, let editingRegion else {
                return
            }

            disableForm = true
            defer {
                disableForm = false
            }

            do {
                try await regionProvider.delete(customRegion: editingRegion)
                self.dismiss()
            } catch {
                self.error = error
            }
        }
    }

    @MainActor
    func doSave() async {
        guard !disableForm, let baseURL = normalizedBaseURL else {
            return
        }

        disableForm = true
        defer {
            disableForm = false
        }

        // Confirm that the Base URL points at a working OneBusAway server before
        // saving, and use its agency list to name the region if the user didn't.
        let agencies: [AgencyWithCoverage]
        do {
            agencies = try await regionProvider.fetchAgenciesWithCoverage(baseURL: baseURL)
        } catch {
            self.error = RegionCustomFormError.serverValidationFailed(baseURL: baseURL, underlyingError: error)
            return
        }

        var name = regionName.strip()
        if name.isEmpty {
            name = agencies.first?.agency?.name ?? Self.defaultRegionName
        }

        let region = Region(
            name: name,
            OBABaseURL: baseURL,
            coordinateRegion: MKCoordinateRegion(serviceArea),
            contactEmail: editingRegion?.contactEmail ?? Self.placeholderContactEmail,
            regionIdentifier: editingRegion?.regionIdentifier
        )

        do {
            try await regionProvider.add(customRegion: region)
            self.dismiss()
        } catch {
            self.error = error
        }
    }
}

enum RegionCustomFormError: LocalizedError {
    case serverValidationFailed(baseURL: URL, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .serverValidationFailed(let baseURL, let underlyingError):
            let format = OBALoc("custom_region_builder_controller.server_validation_error_fmt", value: "Unable to reach a compatible transit API server at %@. Check the Base URL and try again.\n\n%@", comment: "An error message displayed when a custom region's server cannot be validated. First parameter is the server URL, second is the underlying error message.")
            return String(format: format, baseURL.absoluteString, underlyingError.localizedDescription)
        }
    }
}

#if DEBUG
struct RegionCustomForm_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RegionCustomForm(regionProvider: Previews_SampleRegionProvider(), editingRegion: .constant(nil))
        }
        .previewDisplayName("Add new region")

        NavigationView {
            RegionCustomForm(
                regionProvider: Previews_SampleRegionProvider(),
                editingRegion: .constant(.regionForPreview(id: 1, name: "Puget Sound", latitude: 47.59820, longitude: -122.32165, latitudeSpan: 0.33704, longitudeSpan: 0.440483))
            )
        }
        .previewDisplayName("Edit existing region")
    }
}
#endif
