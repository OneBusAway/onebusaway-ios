//
//  RegionPickerCoordinator.swift
//  OBAKit
//
//  Created by Alan Chu on 1/19/23.
//

import OBAKitCore

/// The coordinator for a SwiftUI-friendly (`ObservableObject`) version of `RegionsServices`.
/// Under-the-hood, this class implements RegionsServiceDelegate, which subsequently publishes new values.
class RegionPickerCoordinator: ObservableObject, RegionProvider, RegionsServiceDelegate {
    var regionsService: RegionsService

    init(regionsService: RegionsService) {
        self.regionsService = regionsService

        self.allRegions = regionsService.allRegions
        self.currentRegion = regionsService.currentRegion
        self.automaticallySelectRegion = regionsService.automaticallySelectRegion

        regionsService.addDelegate(self)
    }

    deinit {
        regionsService.removeDelegate(self)
    }

    // MARK: - RegionProvider implementation
    @Published private(set) var allRegions: [Region]
    @Published private(set) var currentRegion: Region?
    @Published var automaticallySelectRegion: Bool {
        didSet {
            regionsService.automaticallySelectRegion = automaticallySelectRegion
        }
    }

    func refreshRegions() async throws {
        try await regionsService.refreshRegions()
    }

    func setCurrentRegion(to newRegion: OBAKitCore.Region) async throws {
        await MainActor.run {
            regionsService.currentRegion = newRegion
        }
    }

    func add(customRegion newRegion: OBAKitCore.Region) async throws {
        try await regionsService.add(customRegion: newRegion)

        await MainActor.run {
            self.allRegions = regionsService.allRegions
        }
    }

    func delete(customRegion region: OBAKitCore.Region) async throws {
        try await regionsService.delete(customRegion: region)

        await MainActor.run {
            self.allRegions = regionsService.allRegions
        }
    }

    // MARK: - RegionsServiceDelegate implementation
    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        Task { @MainActor in
            self.currentRegion = service.currentRegion
        }
    }

    func regionsService(_ service: RegionsService, changedAutomaticRegionSelection value: Bool) {
        Task { @MainActor in
            if service.automaticallySelectRegion != self.automaticallySelectRegion {
                self.automaticallySelectRegion = service.automaticallySelectRegion
            }
        }
    }

    func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        Task { @MainActor in
            self.allRegions = service.allRegions
        }
    }

    func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        Task { @MainActor in
            // Unable to automatically select a region.
            self.automaticallySelectRegion = false
        }
    }
}
