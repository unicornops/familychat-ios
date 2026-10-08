//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import LinkPresentation

nonisolated enum LinkMetadataProviderError: Error {
    case disabled
}

class LinkMetadataProvider: LinkMetadataProviderProtocol {
    /// Family Chat: off whatever the developer options say (#8). The device itself would fetch the linked page,
    /// telling a third-party site that someone was sent that link and from which IP address.
    static let isEnabled = false
    
    private(set) var metadataItems = [URL: LinkMetadataProviderItem]()
    
    func fetchMetadataFor(url: URL) async -> Result<LinkMetadataProviderItem, Error> {
        guard Self.isEnabled else {
            return .failure(LinkMetadataProviderError.disabled)
        }
        
        if let item = metadataItems[url] {
            return .success(item)
        }
        
        do {
            let metadata = try await LPMetadataProvider().startFetchingMetadata(for: url)
            let item = LinkMetadataProviderItem(metadata: metadata)
            metadataItems[url] = item
            return .success(item)
        } catch {
            return .failure(error)
        }
    }
}
