//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Observation

/// Drives one presentation of the parental gate.
///
/// A wrong answer replaces the question with a new one (never the same question twice in a row, also
/// across presentations); after ``maximumWrongAnswers`` the gate closes without opening anything.
@Observable
final class ParentalGateScreenModel {
    static let maximumWrongAnswers = 3
    
    /// The question shown last, by any presentation, so the next one always differs.
    private static var mostRecentChallenge: ParentalGateChallenge?
    
    private(set) var challenge: ParentalGateChallenge
    private(set) var wrongAnswerCount = 0
    private(set) var isFinished = false
    var answer = ""
    
    /// The host (or scheme, e.g. "mailto") the link would open, to show the grown-up where it goes.
    let destination: String?
    
    @ObservationIgnored private let makeChallenge: (ParentalGateChallenge?) -> ParentalGateChallenge
    @ObservationIgnored private let completion: (Bool) -> Void
    
    var canSubmit: Bool {
        !isFinished && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(destination url: URL,
         makeChallenge: @escaping (ParentalGateChallenge?) -> ParentalGateChallenge = { ParentalGateChallenge.random(excluding: $0) },
         completion: @escaping (Bool) -> Void) {
        destination = url.host() ?? url.scheme
        self.makeChallenge = makeChallenge
        self.completion = completion
        challenge = makeChallenge(Self.mostRecentChallenge)
        Self.mostRecentChallenge = challenge
    }
    
    func submit() {
        guard canSubmit else { return }
        
        if challenge.accepts(answer) {
            finish(passed: true)
            return
        }
        
        wrongAnswerCount += 1
        guard wrongAnswerCount < Self.maximumWrongAnswers else {
            finish(passed: false)
            return
        }
        
        challenge = makeChallenge(challenge)
        Self.mostRecentChallenge = challenge
        answer = ""
    }
    
    func cancel() {
        finish(passed: false)
    }
    
    // MARK: - Private
    
    private func finish(passed: Bool) {
        guard !isFinished else { return }
        isFinished = true
        completion(passed)
    }
}
