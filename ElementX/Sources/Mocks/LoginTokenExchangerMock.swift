//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// A hand-written mock (the protocol is not Sourcery-generated) that records the exchange and answers with a fixed result.
final class LoginTokenExchangerMock: LoginTokenExchangerProtocol, @unchecked Sendable {
    struct Configuration {
        var result: Result<LoginTokenCredentials, LoginTokenExchangeError> = .success(.mockAna)
    }
    
    private let configuration: Configuration
    
    private(set) var exchangeCallsCount = 0
    private(set) var exchangeReceivedArguments: (token: String, homeserverURL: URL, initialDeviceName: String?)?
    
    init(_ configuration: Configuration = .init()) {
        self.configuration = configuration
    }
    
    func exchange(token: String, homeserverURL: URL, initialDeviceName: String?) async throws -> LoginTokenCredentials {
        exchangeCallsCount += 1
        exchangeReceivedArguments = (token, homeserverURL, initialDeviceName)
        return try configuration.result.get()
    }
}

extension LoginTokenCredentials {
    static var mockAna: LoginTokenCredentials {
        LoginTokenCredentials(userID: "@ana:smith.safechat.family", accessToken: "syt_access", deviceID: "DEVICE1", refreshToken: nil)
    }
}
