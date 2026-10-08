//
// Copyright 2026 Element Creations Ltd.
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

struct AppSettingsTests {
    @Test
    func defaultAccountProvider() {
        let appSettings = AppSettings.volatile()
        // Family Chat: the only account provider is a wildcard rule, which is not a server to sign in to.
        #expect(appSettings.defaultAccountProvider == .generic(""))
        
        appSettings.previousServers = ["smith.safechat.family"]
        #expect(appSettings.defaultAccountProvider == .generic("smith.safechat.family"))
        
        // A remembered server the account providers no longer allow isn't offered.
        appSettings.override(accountProviders: [.managed(serverName: "example.com", baseURL: "https://matrix.example.com")],
                             allowOtherAccountProviders: false)
        #expect(appSettings.defaultAccountProvider == appSettings.accountProviders[0])
        
        appSettings.override(accountProviders: appSettings.accountProviders, allowOtherAccountProviders: true)
        #expect(appSettings.defaultAccountProvider == .generic("smith.safechat.family"))
    }
}

// MARK: - Helpers

private extension AppSettings {
    func override(accountProviders: [AccountProvider], allowOtherAccountProviders: Bool) {
        override(accountProviders: accountProviders,
                 allowOtherAccountProviders: allowOtherAccountProviders,
                 hideBrandChrome: hideBrandChrome,
                 pushGatewayBaseURL: pushGatewayBaseURL,
                 oAuthRedirectURL: oAuthRedirectURL,
                 oAuthClientURIPath: oAuthClientURIPath,
                 websiteURL: websiteURL,
                 logoURL: logoURL,
                 copyrightURL: copyrightURL,
                 acceptableUseURL: acceptableUseURL,
                 privacyURL: privacyURL,
                 encryptionURL: encryptionURL,
                 deviceVerificationURL: deviceVerificationURL,
                 chatBackupDetailsURL: chatBackupDetailsURL,
                 identityPinningViolationDetailsURL: identityPinningViolationDetailsURL,
                 historySharingDetailsURL: historySharingDetailsURL,
                 elementWebHosts: elementWebHosts,
                 accountProvisioningHost: accountProvisioningHost,
                 bugReportApplicationID: bugReportApplicationID,
                 analyticsTermsURL: analyticsTermsURL,
                 mapTilerConfiguration: mapTilerConfiguration.publisher.value)
    }
}
