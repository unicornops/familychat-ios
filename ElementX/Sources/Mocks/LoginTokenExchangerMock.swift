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
    private(set) var logoutCallsCount = 0
    private(set) var logoutReceivedArguments: (accessToken: String, homeserverURL: URL)?
    /// Called at the start of `exchange`, before it answers; lets a test act while a redemption is in flight.
    var exchangeWillAnswer: (() async -> Void)?
    
    init(_ configuration: Configuration = .init()) {
        self.configuration = configuration
    }
    
    func exchange(token: String, homeserverURL: URL, initialDeviceName: String?) async throws -> LoginTokenCredentials {
        exchangeCallsCount += 1
        exchangeReceivedArguments = (token, homeserverURL, initialDeviceName)
        await exchangeWillAnswer?()
        return try configuration.result.get()
    }
    
    func logout(accessToken: String, homeserverURL: URL) async {
        logoutCallsCount += 1
        logoutReceivedArguments = (accessToken, homeserverURL)
    }
}

extension LoginTokenCredentials {
    static var mockAna: LoginTokenCredentials {
        mock(userID: "@ana:smith.safechat.family")
    }
    
    static func mock(userID: String, refreshToken: String? = nil) -> LoginTokenCredentials {
        LoginTokenCredentials(userID: userID, accessToken: "syt_access", deviceID: "DEVICE1", refreshToken: refreshToken)
    }
}
