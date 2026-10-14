//
//  RESTAPIService+OnDemandPointers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

extension RESTAPIService {
    /// Fetches the service behind every `onDemandServiceIds` pointer at once and
    /// returns those that loaded, in pointer order; a failure is logged and
    /// omitted. Cancelling the calling task cancels every request, and the
    /// caller must check for that itself before using the result.
    nonisolated func loadOnDemandServices(ids: [String], geometryDetail: OnDemandGeometryDetail) async -> [OnDemandService] {
        await withTaskGroup(of: (index: Int, service: OnDemandService?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    do {
                        return (index, try await self.getOnDemandService(id: id, geometryDetail: geometryDetail).entry)
                    } catch {
                        if !Task.isCancelled {
                            Logger.error("On-demand service \(id) failed to load: \(error)")
                        }
                        return (index, nil)
                    }
                }
            }
            var serviceByIndex: [Int: OnDemandService] = [:]
            for await result in group {
                serviceByIndex[result.index] = result.service
            }
            return ids.indices.compactMap { serviceByIndex[$0] }
        }
    }
}
