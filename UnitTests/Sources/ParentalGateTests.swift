//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing
import UIKit

@MainActor
struct ParentalGateTests {
    // MARK: - Number words
    
    @Test(arguments: [(0, "zero"), (7, "seven"), (13, "thirteen"), (19, "nineteen"), (20, "twenty"),
                      (21, "twenty-one"), (47, "forty-seven"), (90, "ninety"), (99, "ninety-nine"),
                      (100, "one hundred"), (101, "one hundred and one"), (115, "one hundred and fifteen"),
                      (340, "three hundred and forty"), (647, "six hundred and forty-seven"),
                      (999, "nine hundred and ninety-nine"), (1000, "one thousand"), (1005, "one thousand and five"),
                      (2340, "two thousand three hundred and forty"),
                      (999_999, "nine hundred and ninety-nine thousand nine hundred and ninety-nine")])
    func englishNumberWords(number: Int, words: String) {
        #expect(ParentalGateNumberWords.english(number) == words)
    }
    
    @Test
    func numberWordsFollowTheLocaleLanguage() {
        // English locales use the tested English words.
        #expect(ParentalGateNumberWords.words(for: 47, locale: Locale(identifier: "en_US")) == "forty-seven")
        #expect(ParentalGateNumberWords.words(for: 647, locale: ParentalGateChallenge.wordsLocale) == "six hundred and forty-seven")
        
        // Other languages use Foundation's spell-out rules for that language, never digits.
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "de_DE")
        let german = ParentalGateNumberWords.words(for: 47, locale: Locale(identifier: "de_DE"))
        #expect(german == formatter.string(from: NSNumber(value: 47)))
        #expect(!german.contains { $0.isNumber })
    }
    
    // MARK: - Challenges
    
    @Test
    func questionsAreWordsWithinAdultLevelRanges() {
        var generator = SeededGenerator(seed: 42)
        
        for _ in 0..<1000 {
            let challenge = ParentalGateChallenge.random(using: &generator)
            
            #expect(!challenge.question.contains { $0.isNumber }, Comment(rawValue: challenge.question))
            
            switch challenge.kind {
            case .typeNumber(let number):
                // Three digits with a hyphenated tens part, e.g. "six hundred and forty-seven".
                #expect((121...999).contains(number))
                #expect(number % 100 >= 21 && number % 10 != 0)
                #expect(challenge.question == "Type the number \(ParentalGateNumberWords.english(number)) in digits.")
                #expect(challenge.answer == number)
            case .multiply(let multiplicand, let multiplier):
                #expect(ParentalGateChallenge.multiplicandRange.contains(multiplicand) && multiplicand != 10)
                #expect(ParentalGateChallenge.multiplierRange.contains(multiplier))
                #expect(challenge.question == "What is \(ParentalGateNumberWords.english(multiplicand)) times \(ParentalGateNumberWords.english(multiplier))?")
                #expect(challenge.answer == multiplicand * multiplier)
            }
        }
    }
    
    @Test
    func challengesAreRandomised() {
        let challenges = (0..<200).map { _ in ParentalGateChallenge.random() }
        
        // Both kinds turn up and the questions vary widely.
        #expect(challenges.contains {
            if case .typeNumber = $0.kind {
                true
            } else {
                false
            }
        })
        #expect(challenges.contains {
            if case .multiply = $0.kind {
                true
            } else {
                false
            }
        })
        #expect(Set(challenges.map(\.question)).count > 100)
    }
    
    @Test
    func aNewChallengeNeverRepeatsThePreviousOne() {
        var generator = SeededGenerator(seed: 7)
        
        // Given the challenge the generator would draw next…
        var lookahead = generator
        let next = ParentalGateChallenge.random(using: &lookahead)
        
        // …excluding it makes the same generator draw something else.
        #expect(ParentalGateChallenge.random(excluding: next, using: &generator) != next)
        
        // And a long run of "wrong answer, new question" never repeats back to back.
        var previous = ParentalGateChallenge.random(using: &generator)
        for _ in 0..<1000 {
            let challenge = ParentalGateChallenge.random(excluding: previous, using: &generator)
            #expect(challenge != previous)
            previous = challenge
        }
    }
    
    @Test
    func answerValidation() {
        let challenge = ParentalGateChallenge(kind: .typeNumber(647))
        
        for accepted in ["647", " 647", "647 ", "\t647\n", "0647", "000647"] {
            #expect(challenge.accepts(accepted), Comment(rawValue: accepted))
        }
        
        for rejected in ["", " ", "646", "6470", "64 7", "+647", "-647", "647.0", "6,47", "0x287",
                         "six hundred and forty-seven", "６４７", "٦٤٧", "647a"] {
            #expect(!challenge.accepts(rejected), Comment(rawValue: rejected))
        }
        
        let multiplication = ParentalGateChallenge(kind: .multiply(13, 7))
        #expect(multiplication.answer == 91)
        #expect(multiplication.question == "What is thirteen times seven?")
        #expect(multiplication.accepts(" 91 "))
        #expect(!multiplication.accepts("137"))
    }
    
    // MARK: - Screen model
    
    @Test
    func correctAnswerPassesOnce() {
        var results: [Bool] = []
        let model = ParentalGateScreenModel(destination: "https://safechat.family/privacy/",
                                            makeChallenge: { _ in .init(kind: .typeNumber(647)) },
                                            completion: { results.append($0) })
        
        #expect(model.destination == "safechat.family")
        #expect(!model.canSubmit)
        
        model.answer = " 647 "
        model.submit()
        model.submit()
        model.cancel()
        
        #expect(results == [true])
        #expect(model.isFinished)
    }
    
    @Test
    func wrongAnswerShowsANewQuestionThenGivesUp() {
        var results: [Bool] = []
        var issued: [ParentalGateChallenge] = []
        let model = ParentalGateScreenModel(destination: "mailto:parent@example.com",
                                            makeChallenge: { previous in
                                                let next = ParentalGateChallenge.random(excluding: previous)
                                                issued.append(next)
                                                return next
                                            },
                                            completion: { results.append($0) })
        
        #expect(model.destination == "mailto")
        
        for attempt in 1...ParentalGateScreenModel.maximumWrongAnswers {
            let question = model.challenge
            model.answer = String(question.answer + 1)
            model.submit()
            
            guard attempt < ParentalGateScreenModel.maximumWrongAnswers else { break }
            
            // A wrong answer replaces the question and clears the field, without finishing.
            #expect(model.challenge != question)
            #expect(model.answer.isEmpty)
            #expect(model.wrongAnswerCount == attempt)
            #expect(results.isEmpty)
        }
        
        // Too many wrong answers close the gate without passing.
        #expect(results == [false])
        #expect(model.isFinished)
        #expect(issued.count == ParentalGateScreenModel.maximumWrongAnswers)
    }
    
    @Test
    func cancellingNeverPasses() {
        var results: [Bool] = []
        let model = ParentalGateScreenModel(destination: "tel:+353123456",
                                            makeChallenge: { _ in .init(kind: .multiply(12, 7)) },
                                            completion: { results.append($0) })
        
        model.cancel()
        model.answer = "84"
        model.submit()
        
        #expect(results == [false])
    }
    
    // MARK: - Central opener
    
    @Test
    func externalURLsAreNotOpenedUntilTheGateIsPassed() {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter, internalURLHandler: { _ in false }, systemOpener: { opened.append($0) })
        var outcomes: [ParentalGate.Outcome] = []
        
        for url: URL in ["https://example.com/page", "mailto:someone@example.com", "tel:+353123456", "sms:+353123456",
                         "maps://?ll=1,2", "https://safechat.family/privacy/", "https://github.com/unicornops/familychat-ios"] {
            gate.openExternalURL(url) { outcomes.append($0) }
            
            // The gate is showing and nothing has been opened yet.
            #expect(presenter.presentedURLs.last == url)
            #expect(opened.isEmpty)
            
            presenter.finish(passed: false)
        }
        
        #expect(opened.isEmpty)
        #expect(outcomes == Array(repeating: .notOpened, count: 7))
    }
    
    @Test
    func externalURLOpensAfterPassingTheGate() {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter, internalURLHandler: { _ in false }, systemOpener: { opened.append($0) })
        var outcomes: [ParentalGate.Outcome] = []
        let url: URL = "https://example.com/page"
        
        gate.openExternalURL(url) { outcomes.append($0) }
        #expect(opened.isEmpty)
        
        presenter.finish(passed: true)
        
        #expect(opened == [url])
        #expect(outcomes == [.opened])
    }
    
    @Test
    func thisAppsSystemSettingsOpenWithoutTheGate() throws {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter, internalURLHandler: { _ in false }, systemOpener: { opened.append($0) })
        var outcomes: [ParentalGate.Outcome] = []
        let settingsURL = try #require(URL(string: UIApplication.openSettingsURLString))
        
        gate.openExternalURL(settingsURL) { outcomes.append($0) }
        
        #expect(presenter.presentedURLs.isEmpty)
        #expect(opened == [settingsURL])
        #expect(outcomes == [.openedAppSettings])
    }
    
    @Test
    func onlyOneGateShowsAtATime() {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter) { opened.append($0) }
        var outcomes: [ParentalGate.Outcome] = []
        
        gate.openExternalURL("https://example.com/first") { outcomes.append($0) }
        gate.openExternalURL("https://example.com/second") { outcomes.append($0) }
        
        #expect(presenter.presentedURLs.count == 1)
        #expect(outcomes == [.notOpened])
        
        presenter.finish(passed: true)
        
        #expect(opened == ["https://example.com/first"])
        #expect(outcomes == [.notOpened, .opened])
    }
    
    @Test
    func internalRoutesBypassTheGate() throws {
        let appRouteURLParser = AppRouteURLParser(appSettings: AppSettings.volatile())
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        var routed: [URL] = []
        let gate = ParentalGate(presenter: presenter,
                                internalURLHandler: { url in
                                    guard appRouteURLParser.route(from: url) != nil else { return false }
                                    routed.append(url)
                                    return true
                                },
                                systemOpener: { opened.append($0) })
        var outcomes: [ParentalGate.Outcome] = []
        
        let scheme = InfoPlistReader.app.appScheme
        let internalURLs = try [
            #require(URL(string: "https://safechat.family/app/login?account_provider=smith.safechat.family")),
            #require(URL(string: "\(scheme)://safechat.family/app/login?account_provider=smith.safechat.family")),
            #require(URL(string: "https://matrix.to/#/@ana:smith.safechat.family")),
            #require(URL(string: "https://matrix.to/#/!room:smith.safechat.family"))
        ]
        
        for url in internalURLs {
            gate.openExternalURL(url) { outcomes.append($0) }
        }
        
        // The app routes its own links itself: no gate and nothing handed to the system.
        #expect(routed == internalURLs)
        #expect(presenter.presentedURLs.isEmpty)
        #expect(opened.isEmpty)
        #expect(outcomes == Array(repeating: .handledInternally, count: internalURLs.count))
        
        // While a look-alike on the same domain is still gated.
        gate.openExternalURL("https://safechat.family/privacy/")
        #expect(presenter.presentedURLs == ["https://safechat.family/privacy/"])
    }
}

// MARK: - Helpers

@MainActor
private final class ParentalGatePresenterSpy: ParentalGatePresenterProtocol {
    private(set) var presentedURLs: [URL] = []
    private var pendingCompletion: ((Bool) -> Void)?
    
    func presentGate(for url: URL, completion: @escaping (Bool) -> Void) {
        presentedURLs.append(url)
        pendingCompletion = completion
    }
    
    func finish(passed: Bool) {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(passed)
    }
}

/// SplitMix64, so the randomised tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        state = seed
    }
    
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
