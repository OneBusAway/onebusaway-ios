//
//  RegionPickerView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/2/23.
//

import MapKit
import SwiftUI
import OBAKitCore

protocol RegionsProvider: ObservableObject {
    var regions: [Region] { get }

    func refreshRegions() async throws
    func setSelectedRegion(to newRegion: Region) async throws
}

struct RegionPickerView<Provider: RegionsProvider>: View {
    @ObservedObject public var regionsProvider: Provider
    @Environment(\.dismiss) var dismiss

    /// The currently selected region.
    @State var selectedRegion: Region?

    /// Whether to disable the `List` interactions. This is set to `true` during certain tasks.
    @State var disableInteractions: Bool = false

    /// An error to display above the [Continue] button.
    @State var taskError: Error?

    var body: some View {
        List {
            Picker("", selection: $selectedRegion) {
                ForEach(regionsProvider.regions, id: \.self) { region in
                    Text(region.name)
                        .tag(Optional(region))  // The tag type must match the selection type (an *optional* Region)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()         // Hide picker header (title)
        }
        .disabled(disableInteractions)
        .refreshable(action: doRefreshRegions)
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
            OnboardingHeaderView(imageSystemName: "globe", headerText: "Choose A Region")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                if let taskError {
                    Text(taskError.localizedDescription)
                }

                RegionPickerMap(mapRect: Binding(get: {
                    selectedRegion?.serviceRect
                }, set: { _ in }), mapHeight: 200)
                    .zIndex(-1) // Make the Map moving transition occur below the [Continue] button.

                TaskButton(action: doSetCurrentRegion) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .disabled(selectedRegion == nil)
                .buttonStyle(.borderedProminent)
            }
            .background(.background)
        }
        .padding()
    }

    @Sendable
    func doSetCurrentRegion() async {
        disableInteractions = true
        defer {
            disableInteractions = false
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        guard let selectedRegion else {
            return
        }

        do {
            try await regionsProvider.setSelectedRegion(to: selectedRegion)
            taskError = nil

            self.dismiss()
        } catch {
            taskError = error
        }
    }

    @Sendable
    func doRefreshRegions() async {
        do {
            try await regionsProvider.refreshRegions()
            taskError = nil
        } catch {
            taskError = error
        }
    }
}

#if DEBUG
struct RegionPickerView_Previews: PreviewProvider {
    class ExampleProvider: ObservableObject, RegionsProvider {
        @Published var regions: [Region] = [
            .init(id: 0, name: "Tampa Bay", latitude: 27.9769105, longitude: -82.445851, latitudeSpan: 0.5424609, longitudeSpan: 0.5763579),
            .init(id: 1, name: "Puget Sound", latitude: 47.59820, longitude: -122.32165, latitudeSpan: 0.33704, longitudeSpan: 0.440483),
            .init(id: 2, name: "MTA New York", latitude: 40.707678, longitude: -74.017681, latitudeSpan: 0.40939, longitudeSpan: 0.468666),
            .init(id: 3, name: "Atlanta", latitude: 33.74819, longitude: -84.39086, latitudeSpan: 0.066268, longitudeSpan: 0.051677),
            .init(id: 15, name: "Adelaide Metro", latitude: -34.833098, longitude: 138.621111, latitudeSpan: 0.52411, longitudeSpan: 0.285071)
        ]

        func refreshRegions() async throws {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            throw NSError(domain: "org.onebusaway.iphone", code: 418, userInfo: [
                NSLocalizedDescriptionKey: "Refresh Regions error!"
            ])
        }

        func setSelectedRegion(to newRegion: Region) async throws {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            throw NSError(domain: "org.onebusaway.iphone", code: 418, userInfo: [
                NSLocalizedDescriptionKey: "Set Selected Region error!"
            ])
        }
    }

    static var previews: some View {
        Text("Hello, World!")
            .sheet(isPresented: .constant(true)) {
                RegionPickerView(regionsProvider: ExampleProvider())
            }
    }
}

extension Region {
    fileprivate convenience init(
        id: RegionIdentifier,
        name: String,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        latitudeSpan: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) {

        let origin = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let span = MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        let region = MKCoordinateRegion(center: origin, span: span)

        self.init(name: name, OBABaseURL: URL(string: "www.example.com")!, coordinateRegion: region, contactEmail: "example@example.com", regionIdentifier: id)
    }
}
#endif
