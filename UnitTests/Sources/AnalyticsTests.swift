//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AnalyticsEvents
@testable import ElementX
import Testing

@MainActor
final class AnalyticsTests {
    /// Family Chat links no analytics SDK, so `AppSettings.analyticsConfiguration` is always `nil`
    /// and the app uses `NoopAnalyticsClient`. The client test below uses an explicit configuration.
    private static let testConfiguration = AnalyticsConfiguration(host: "https://analytics.localhost", apiKey: "test_key")
    
    private let appSettings: AppSettings
    private let analytics: AnalyticsServiceProtocol
    private let analyticsClient: AnalyticsClientMock
    
    init() {
        appSettings = AppSettings.volatile()
        
        analyticsClient = AnalyticsClientMock()
        analyticsClient.isRunning = false
        analytics = AnalyticsService(client: analyticsClient, appSettings: appSettings)
    }
    
    @Test
    func analyticsPromptNewUser() {
        // Given a fresh install of the app.
        // When the user would be prompted for analytics.
        let showPrompt = analytics.shouldShowAnalyticsPrompt
        
        // Then no prompt should be shown as Family Chat ships without analytics.
        #expect(!showPrompt, "No prompt should be shown when analytics are disabled.")
    }
    
    @Test
    func analyticsPromptUserDeclinedAnalytics() {
        // Given an existing install of the app where the user previously declined analytics
        appSettings.analyticsConsentState = .optedOut
        
        // When the user is prompted for analytics
        let showPrompt = analytics.shouldShowAnalyticsPrompt
        
        // Then no prompt should be shown.
        #expect(!showPrompt, "A prompt should not be shown any more.")
    }
    
    @Test
    func analyticsPromptUserAcceptedAnalytics() {
        // Given an existing install of the app where the user previously accepted analytics
        appSettings.analyticsConsentState = .optedIn
        
        // When the user is prompted for analytics
        let showPrompt = analytics.shouldShowAnalyticsPrompt
        
        // Then no prompt should be shown.
        #expect(!showPrompt, "A prompt should not be shown any more.")
    }
    
    @Test
    func analyticsPromptNotDisplayed() {
        // Given a fresh install of the app Analytics should be disabled
        #expect(appSettings.analyticsConsentState == .unknown)
        #expect(!analytics.isEnabled)
        #expect(!analyticsClient.startAnalyticsConfigurationCalled)
    }
    
    @Test
    func analyticsOptOut() {
        // Given a fresh install of the app (without analytics having been set).
        // When analytics is opt-out
        analytics.optOut()
        // Then analytics should be disabled
        #expect(appSettings.analyticsConsentState == .optedOut)
        #expect(!analytics.isEnabled)
        #expect(!analyticsClient.isRunning)
        // Analytics client should have been stopped
        #expect(analyticsClient.stopCalled)
    }
    
    @Test
    func analyticsOptIn() {
        // Given a fresh install of the app (without analytics having been set).
        // When analytics is opt-in
        analytics.optIn()
        // The analytics should be enabled
        #expect(appSettings.analyticsConsentState == .optedIn)
        #expect(analytics.isEnabled)
        // But the client can't start because Family Chat ships without an analytics configuration.
        #expect(!analyticsClient.startAnalyticsConfigurationCalled)
    }
    
    @Test
    func analyticsStartIfNotEnabled() {
        // Given an existing install of the app where the user previously declined the tracking
        appSettings.analyticsConsentState = .optedOut
        // Analytics should not start
        #expect(!analytics.isEnabled)
        analytics.startIfEnabled()
        #expect(!analyticsClient.startAnalyticsConfigurationCalled)
    }
    
    @Test
    func analyticsStartIfEnabled() {
        // Given an existing install of the app where the user previously accepted the tracking
        appSettings.analyticsConsentState = .optedIn
        // Analytics would start, but Family Chat ships without an analytics configuration.
        #expect(analytics.isEnabled)
        analytics.startIfEnabled()
        #expect(!analyticsClient.startAnalyticsConfigurationCalled)
    }
    
    @Test
    func resetConsentState() {
        // Given an existing install of the app where the user previously accpeted the tracking
        appSettings.analyticsConsentState = .optedIn
        #expect(!analytics.shouldShowAnalyticsPrompt)
        
        // When forgetting analytics consents
        analytics.resetConsentState()
        
        // Then the consent state should be cleared. Family Chat ships without analytics,
        // so the prompt still isn't shown.
        #expect(appSettings.analyticsConsentState == .unknown)
        #expect(!analytics.shouldShowAnalyticsPrompt)
    }
    
    @Test
    func noopClientNeverRuns() {
        // Given the client the app ships with
        let client = NoopAnalyticsClient()
        #expect(!client.isRunning)
        
        // When it is started, even with a configuration, and sent events
        client.start(analyticsConfiguration: Self.testConfiguration)
        client.screen(AnalyticsEvent.MobileScreen(durationMs: nil, screenName: .Home))
        client.capture(AnalyticsEvent.CreatedRoom(isDM: false))
        
        // Then it still isn't running
        #expect(!client.isRunning)
    }
    
    @Test
    func noopClientServiceNeverStarts() {
        // Given the service as the app builds it, with a user who opted in on an earlier build
        let service = AnalyticsService(client: NoopAnalyticsClient(), appSettings: appSettings)
        appSettings.analyticsConsentState = .optedIn
        
        // When the app tries to start it
        service.startIfEnabled()
        
        // Then there is still no prompt and nothing to send
        #expect(!service.shouldShowAnalyticsPrompt)
        #expect(!appSettings.canPromptForAnalytics)
    }
}
