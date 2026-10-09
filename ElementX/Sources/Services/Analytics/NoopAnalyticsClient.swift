//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AnalyticsEvents

/// Family Chat: the analytics client used in place of upstream's PostHog client (#8).
///
/// The app is for children, so it ships no analytics SDK at all. This client never
/// starts and drops every event, which keeps `AnalyticsService` and its call sites
/// unchanged from upstream.
final class NoopAnalyticsClient: AnalyticsClientProtocol {
    var isRunning: Bool {
        false
    }
    
    func start(analyticsConfiguration: AnalyticsConfiguration) { }
    
    func reset() { }
    
    func stop() { }
    
    func capture(_ event: AnalyticsEventProtocol) { }
    
    func screen(_ event: AnalyticsScreenProtocol) { }
    
    func updateUserProperties(_ event: AnalyticsEvent.UserProperties) { }
}
