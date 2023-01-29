//
//  RegionPickerView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/2/23.
//

import MapKit
import SwiftUI
import OBAKitCore

struct RegionPickerView: View {
    class RegionsProvider: ObservableObject {
        var availableRegions: [RegionViewModel]

        init(availableRegions: [RegionViewModel]) {
            self.availableRegions = availableRegions
        }
    }

    struct RegionViewModel: Identifiable, Hashable {
        var id: RegionIdentifier

        var name: String
        var serviceRect: MKMapRect

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        init(_ region: Region) {
            self.id = region.regionIdentifier
            self.name = region.name
            self.serviceRect = region.serviceRect
        }

        init(
            id: Int,
            name: String,
            latitude: CLLocationDegrees,
            longitude: CLLocationDegrees,
            width: Double,
            height: Double
        ) {
            self.id = id
            self.name = name

            let origin = MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            let size = MKMapSize(width: width, height: height)
            self.serviceRect = MKMapRect(origin: origin, size: size)
        }
    }

    @ObservedObject var regionsProvider: RegionsProvider
    @State var selectedRegionServiceRect: MKMapRect?
    @State var selectedRegion: RegionViewModel?

    var body: some View {
        List(regionsProvider.availableRegions, id: \.self, selection: $selectedRegion) { region in
            HStack {
                Image(systemName: region == selectedRegion ? "checkmark.circle.fill" : "circle")
                Text(region.name)
            }
        }
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .onChange(of: selectedRegion) { newValue in
            if let newValue {
                self.selectedRegionServiceRect = newValue.serviceRect
            }
        }
        .safeAreaInset(edge: .top) {
            OnboardingHeaderView(imageSystemName: "globe", headerText: "Choose A Region")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                RegionPickerMap(mapRect: Binding(get: {
                    selectedRegion?.serviceRect
                }, set: { _ in }), mapHeight: 200)
                    .zIndex(-1) // Make the Map moving transition occur below the [Continue] button.

                Button {
                    print()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
            }
            .background(.background)
        }
        .padding()
        .environment(\.editMode, .constant(.active))
    }
}

struct OnboarderView_Previews: PreviewProvider {

    static var regions: [RegionPickerView.RegionViewModel] = [
        .init(id: 0, name: "Tampa Bay", latitude: 28.248141, longitude: -82.85053, width: 516632.36992569268, height: 476938.48868602514),
        .init(id: 1, name: "Puget Sound", latitude: 48.643, longitude: -123.3964, width: 1338771.0533083975, height: 1897888.1099742651),
        .init(id: 2, name: "MTA New York", latitude: 40.933636, longitude: -74.252014, width: 349462.6983935982, height: 423682.60784052312),
        .init(id: 3, name: "Atlanta", latitude: 34.25758321919466, longitude: -84.7740422485, width: 646238.98815335333, height: 782487.9430911541),
        .init(id: 15, name: "Adelaide Metro", latitude: -34.571043, longitude: 138.445316, width: 440510.78549051285, height: 698882.80236634612)
    ]

    static var sampleRegionProvider: RegionPickerView.RegionsProvider = {
        var provider = RegionPickerView.RegionsProvider(availableRegions: regions)
        return provider
    }()

    static var previews: some View {
        RegionPickerView(regionsProvider: sampleRegionProvider)
    }
}
