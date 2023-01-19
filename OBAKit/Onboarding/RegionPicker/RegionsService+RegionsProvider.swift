//
//  RegionsService+RegionsProvider.swift
//  OBAKit
//
//  Created by Alan Chu on 1/19/23.
//

import OBAKitCore

extension RegionsService: RegionsProvider {
    func setCurrentRegion(to newRegion: Region) async throws {
        await MainActor.run {
            self.currentRegion = newRegion

            // When selecting a region from the RegionPickerBulletin, ensure that automaticallySelectRegion is false.
            // Since the user is manually selecting a Region, it doesn't make sense to leave control with the app on
            // this decision any longer.
            self.automaticallySelectRegion = false
        }
    }
}
