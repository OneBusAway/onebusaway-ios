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
        }
    }
}
