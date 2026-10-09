//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Performance instrumentation hooks.
///
/// Family Chat: upstream reports these transactions to Sentry. The app ships without
/// Sentry (#8), so this keeps upstream's API for the call sites but records nothing.
class Signposter {
    enum TransactionName: Hashable {
        case cachedRoomList
        case upToDateRoomList
        case notificationToMessage
        case openRoom
        case sendMessage(uuid: String)
    }
    
    enum SpanName: String {
        case timelineLoad = "Timeline load"
    }
    
    struct Span {
        func finish() { }
    }
    
    enum TagName: String {
        case homeserver
    }
    
    // MARK: - Transactions
    
    func startTransaction(_ transactionName: TransactionName, operation: String = "ux", tags: [TagName: String] = [:]) { }
    
    func finishTransaction(_ transactionName: TransactionName) { }
    
    func resetTransactions() { }
    
    // MARK: - Spans
    
    func addSpan(_ spanName: SpanName, toTransaction transactionName: TransactionName) -> Span? {
        nil
    }
    
    // MARK: - Tags
    
    func addGlobalTag(_ tagName: TagName, value: String) { }
}
