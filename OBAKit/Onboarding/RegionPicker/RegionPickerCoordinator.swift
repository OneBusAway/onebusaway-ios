//
//  RegionPickerCoordinator.swift
//  OBAKit
//
//  Created by Alan Chu on 1/19/23.
//

import OBAKitCore

/// The coordinator for a SwiftUI-friendly (`ObservableObject`) version of `RegionsServices`.
/// Under-the-hood, this class implements RegionsServiceDelegate, which subsequently publishes new values.
public class RegionPickerCoordinator: ObservableObject, RegionProvider, RegionsServiceDelegate {
    var regionsService: RegionsService
    var userDataStore: UserDataStore

    public init(regionsService: RegionsService, userDataStore: UserDataStore) {
        self.regionsService = regionsService
        self.userDataStore = userDataStore

        self.allRegions = regionsService.allRegions
        self.currentRegion = regionsService.currentRegion
        self.automaticallySelectRegion = regionsService.automaticallySelectRegion

        regionsService.addDelegate(self)
    }

    /// Convenience initializer for backward compatibility
    public convenience init(regionsService: RegionsService) {
        // Get userDataStore from the regionsService's parent application
        // This is a temporary solution - in practice, pass userDataStore explicitly
        let userDataStore = UserDefaultsStore(userDefaults: UserDefaults.standard)
        self.init(regionsService: regionsService, userDataStore: userDataStore)
    }

    deinit {
        regionsService.removeDelegate(self)
    }

    // MARK: - RegionProvider implementation
    @Published public private(set) var allRegions: [Region]
    @Published public private(set) var currentRegion: Region?
    @Published public var automaticallySelectRegion: Bool {
        didSet {
            regionsService.automaticallySelectRegion = automaticallySelectRegion
        }
    }

    public func refreshRegions() async throws {
        try await regionsService.refreshRegions()
    }

    public func setCurrentRegion(to newRegion: OBAKitCore.Region) async throws {
        await MainActor.run {
            regionsService.currentRegion = newRegion
        }
    }

    public func add(customRegion newRegion: OBAKitCore.Region) async throws {
        try await regionsService.add(customRegion: newRegion)

        await MainActor.run {
            self.allRegions = regionsService.allRegions
            self.automaticallySelectRegion = false
        }

        // Automatically set new regions to be the current region.
        try await setCurrentRegion(to: newRegion)
    }

    public func delete(customRegion region: OBAKitCore.Region) async throws {
        try await regionsService.delete(customRegion: region)

        await MainActor.run {
            self.allRegions = regionsService.allRegions
        }
    }

    // MARK: - RegionsServiceDelegate implementation
    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        Task { @MainActor in
            self.currentRegion = service.currentRegion
        }
    }

    public func regionsService(_ service: RegionsService, changedAutomaticRegionSelection value: Bool) {
        Task { @MainActor in
            if service.automaticallySelectRegion != self.automaticallySelectRegion {
                self.automaticallySelectRegion = service.automaticallySelectRegion
            }
        }
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        Task { @MainActor in
            self.allRegions = service.allRegions
        }
    }

    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        Task { @MainActor in
            // Unable to automatically select a region.
            self.automaticallySelectRegion = false
        }
    }

    // MARK: - Trip Planning

    public func isTripPlanningEnabled(for region: Region) -> Bool {
        return userDataStore.isTripPlanningEnabled(for: region)
    }

    public func setTripPlanningEnabled(_ enabled: Bool, for region: Region) {
        userDataStore.setTripPlanningEnabled(enabled, for: region)
    }
}
