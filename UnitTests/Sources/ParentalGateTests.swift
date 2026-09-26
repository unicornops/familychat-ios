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
        #expect(ParentalGateNumberWords.words(for: 23, locale: ParentalGateChallenge.wordsLocale) == "twenty-three")
        
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
    func questionsAreMultiplicationsInWordsWithinAdultLevelRanges() {
        var generator = SeededGenerator(seed: 42)
        
        for _ in 0..<1000 {
            let challenge = ParentalGateChallenge.random(using: &generator)
            
            #expect(!challenge.question.contains { $0.isNumber }, Comment(rawValue: challenge.question))
            #expect((13...49).contains(challenge.multiplicand) && !challenge.multiplicand.isMultiple(of: 10))
            #expect((3...9).contains(challenge.multiplier))
            #expect(challenge.question == "What is \(ParentalGateNumberWords.english(challenge.multiplicand)) times \(ParentalGateNumberWords.english(challenge.multiplier))?")
            #expect(challenge.answer == challenge.multiplicand * challenge.multiplier)
        }
    }
    
    @Test
    func challengesAreRandomised() {
        let challenges = (0..<200).map { _ in ParentalGateChallenge.random() }
        
        #expect(Set(challenges.map(\.question)).count > 100)
        #expect(Set(challenges.map(\.multiplier)).count == 7)
        #expect(Set(challenges.map(\.multiplicand)).count > 20)
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
        let challenge = ParentalGateChallenge(multiplicand: 23, multiplier: 7)
        #expect(challenge.question == "What is twenty-three times seven?")
        #expect(challenge.answer == 161)
        
        for accepted in ["161", " 161", "161 ", "\t161\n", "0161", "000161"] {
            #expect(challenge.accepts(accepted), Comment(rawValue: accepted))
        }
        
        for rejected in ["", " ", "160", "1610", "16 1", "+161", "-161", "161.0", "1,61", "0xA1",
                         "one hundred and sixty-one", "１６１", "١٦١", "161a", "237"] {
            #expect(!challenge.accepts(rejected), Comment(rawValue: rejected))
        }
    }
    
    // MARK: - Screen model
    
    @Test
    func correctAnswerPassesOnce() {
        var results: [Bool] = []
        let model = ParentalGateScreenModel(destination: "https://safechat.family/privacy/",
                                            makeChallenge: { _ in .init(multiplicand: 23, multiplier: 7) },
                                            completion: { results.append($0) })
        
        #expect(model.destination == "safechat.family")
        #expect(!model.canSubmit)
        
        model.answer = " 161 "
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
                                            makeChallenge: { _ in .init(multiplicand: 12, multiplier: 7) },
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
        
        // Links on the app's own domain that it can't route are still gated, `/app/…` without
        // `account_provider` included.
        for url: URL in ["https://safechat.family/privacy/", "https://safechat.family/app/x", "https://safechat.family/app/login"] {
            gate.openExternalURL(url)
            #expect(presenter.presentedURLs.last == url)
            presenter.finish(passed: false)
        }
        #expect(routed == internalURLs)
        #expect(opened.isEmpty)
    }
    
    @Test
    func phishingLinksAreUnwrappedAndFlaggedAtTheGate() throws {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter, internalURLHandler: { _ in false }, systemOpener: { opened.append($0) })
        
        // Given a link whose text looks like a different URL, as the message formatter wraps it.
        let realURL: URL = "https://evil.example.com/login"
        var components = URLComponents()
        components.scheme = URL.confirmationScheme
        components.queryItems = ConfirmURLParameters(internalURL: realURL, displayString: "https://safechat.family").urlQueryItems
        let wrappedURL = try #require(components.url)
        
        gate.openExternalURL(wrappedURL)
        
        // Then the gate shows the real destination and the misleading text, and opens the real URL.
        #expect(presenter.presentedURLs == [realURL])
        #expect(presenter.presentedLinkTexts == ["https://safechat.family"])
        presenter.finish(passed: true)
        #expect(opened == [realURL])
        
        let model = ParentalGateScreenModel(destination: realURL, linkText: "https://safechat.family") { _ in }
        #expect(model.linkTextWarning?.contains("https://safechat.family") == true)
        #expect(model.linkTextWarning?.contains(realURL.absoluteString) == true)
    }
    
    @Test
    func ownDomainLinksOpenInTheBrowserNotBackInTheApp() {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter, internalURLHandler: { _ in false }, systemOpener: { opened.append($0) })
        
        for url: URL in ["https://safechat.family/app/x", "https://app.safechat.family/about?x=1", "https://example.com/app/x"] {
            gate.openExternalURL(url)
            presenter.finish(passed: true)
        }
        
        #expect(opened == ["https://safechat.family/app/x?no_universal_links=true",
                           "https://app.safechat.family/about?x=1&no_universal_links=true",
                           "https://example.com/app/x"])
        #expect(ParentalGate.browserURL(for: "https://safechat.family/a?no_universal_links=true") == "https://safechat.family/a?no_universal_links=true")
    }
    
    // MARK: - Wiring
    
    @Test
    func appMediatorOpensThroughTheGate() {
        let presenter = ParentalGatePresenterSpy()
        var opened: [URL] = []
        let gate = ParentalGate(presenter: presenter, internalURLHandler: { _ in false }, systemOpener: { opened.append($0) })
        let appMediator = AppMediator(windowManager: WindowManagerMock(), networkMonitor: NetworkMonitorMock(), parentalGate: gate)
        var results: [Bool] = []
        
        appMediator.open("https://example.com/help")
        #expect(presenter.presentedURLs == ["https://example.com/help"])
        #expect(opened.isEmpty)
        presenter.finish(passed: false)
        
        appMediator.open("otherapp://sign-in") { results.append($0) }
        presenter.finish(passed: false)
        appMediator.open("otherapp://sign-in") { results.append($0) }
        presenter.finish(passed: true)
        
        #expect(results == [false, true])
        #expect(opened == ["otherapp://sign-in"])
    }
    
    // MARK: - Window presenter
    
    @Test
    func presenterFailsWithoutAWindowScene() {
        let presenter = ParentalGateWindowPresenter(notificationCenter: NotificationCenter()) { nil }
        var results: [Bool] = []
        
        presenter.presentGate(for: "https://example.com", linkText: nil) { results.append($0) }
        
        #expect(results == [false])
        #expect(!presenter.isPresenting)
    }
    
    @Test
    func presenterCancelsWhenItsSceneLeaves() throws {
        let windowScene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        
        for notification in [UIScene.didEnterBackgroundNotification, UIScene.didDisconnectNotification] {
            let notificationCenter = NotificationCenter()
            let presenter = ParentalGateWindowPresenter(notificationCenter: notificationCenter) { windowScene }
            var results: [Bool] = []
            
            presenter.presentGate(for: "https://example.com", linkText: nil) { results.append($0) }
            #expect(presenter.isPresenting)
            
            // Another scene going away leaves this gate alone…
            notificationCenter.post(name: notification, object: NSObject())
            #expect(results.isEmpty)
            
            // …while its own scene going away cancels it, so the gate can never be left waiting.
            notificationCenter.post(name: notification, object: windowScene)
            #expect(results == [false])
            #expect(!presenter.isPresenting)
        }
    }
    
    // MARK: - Edit menus
    
    @Test
    func editMenusLoseTheItemsThatLeaveTheApp() {
        let copy = UICommand(title: "Copy", action: #selector(UIResponderStandardEditActions.copy(_:)))
        let searchWeb = UICommand(title: "Search Web", action: Selector(("_searchWeb:")))
        let translate = UICommand(title: "Translate", action: Selector(("_translate:")))
        let lookUp = UIMenu(title: "", identifier: .lookup, options: .displayInline, children: [UICommand(title: "Look Up", action: Selector(("_define:")))])
        let share = UICommand(title: "Share…", action: Selector(("_share:")))
        let nested = UIMenu(title: "", options: .displayInline, children: [searchWeb, share])
        
        let menu = ParentalGateEditMenu.menu(from: [copy, lookUp, translate, nested])
        
        let titles = flattenedTitles(menu.children)
        #expect(titles == ["Copy", "Share…"])
    }
    
    private func flattenedTitles(_ elements: [UIMenuElement]) -> [String] {
        elements.flatMap { element -> [String] in
            if let menu = element as? UIMenu {
                return flattenedTitles(menu.children)
            }
            return [element.title]
        }
    }
}

// MARK: - Helpers

@MainActor
private final class ParentalGatePresenterSpy: ParentalGatePresenterProtocol {
    private(set) var presentedURLs: [URL] = []
    private(set) var presentedLinkTexts: [String?] = []
    private var pendingCompletion: ((Bool) -> Void)?
    
    func presentGate(for url: URL, linkText: String?, completion: @escaping (Bool) -> Void) {
        presentedURLs.append(url)
        presentedLinkTexts.append(linkText)
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
