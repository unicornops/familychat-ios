//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// An adult-level question for the parental gate (unicornops/family-chat#232 decision 10).
///
/// Always a multiplication of a two-digit number by a single digit, both written in words, e.g.
/// "What is twenty-three times seven?". Words stop a child copying digits into a calculator, and the
/// two-digit operand (13–49, never a round ten) keeps it beyond the times tables younger children know
/// by heart while staying quick mental arithmetic for an adult. The answer is typed in digits.
nonisolated struct ParentalGateChallenge: Equatable, Sendable {
    static let multiplicandRange = 13...49
    static let multiplierRange = 3...9
    
    /// The question strings are only in English (`Untranslated.strings`), so the number words are English
    /// too. When the questions get translated, pass the UI language here instead and
    /// ``ParentalGateNumberWords/words(for:locale:)`` switches to Foundation's spell-out rules.
    static let wordsLocale = Locale(identifier: "en_GB")
    
    let multiplicand: Int
    let multiplier: Int
    
    var answer: Int {
        multiplicand * multiplier
    }
    
    var question: String {
        UntranslatedL10n.screenParentalGateQuestionMultiply(Self.words(multiplicand), Self.words(multiplier))
    }
    
    /// Draws a random challenge that is never equal to `previous`, so a wrong answer can't be retried
    /// against the same question.
    static func random(excluding previous: ParentalGateChallenge? = nil) -> ParentalGateChallenge {
        var generator = SystemRandomNumberGenerator()
        return random(excluding: previous, using: &generator)
    }
    
    static func random(excluding previous: ParentalGateChallenge? = nil,
                       using generator: inout some RandomNumberGenerator) -> ParentalGateChallenge {
        while true {
            let candidate = ParentalGateChallenge(multiplicand: randomMultiplicand(using: &generator),
                                                  multiplier: Int.random(in: multiplierRange, using: &generator))
            if candidate != previous {
                return candidate
            }
        }
    }
    
    /// Whether `input` is the answer written in ASCII digits. Surrounding whitespace and leading zeros are
    /// accepted; signs, separators, spaces between digits and words are not.
    func accepts(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isWholeNumber }) else {
            return false
        }
        return Int(trimmed) == answer
    }
    
    // MARK: - Private
    
    private static func words(_ number: Int) -> String {
        ParentalGateNumberWords.words(for: number, locale: wordsLocale)
    }
    
    private static func randomMultiplicand(using generator: inout some RandomNumberGenerator) -> Int {
        while true {
            let multiplicand = Int.random(in: multiplicandRange, using: &generator)
            if !multiplicand.isMultiple(of: 10) {
                return multiplicand
            }
        }
    }
}

/// Writes whole numbers in words for the parental gate's questions.
nonisolated enum ParentalGateNumberWords {
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                                "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                                "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    
    /// `number` in words in `locale`'s language. English is written here (British style, "one hundred and
    /// five") so the questions are predictable and tested; other languages use Foundation's spell-out rules.
    static func words(for number: Int, locale: Locale) -> String {
        if locale.language.languageCode == .english {
            return english(number)
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: number)) ?? english(number)
    }
    
    /// English words for `number` in `0...999_999`, e.g. "six hundred and forty-seven".
    static func english(_ number: Int) -> String {
        precondition((0...999_999).contains(number), "Only numbers from 0 to 999,999 are supported.")
        
        if number >= 1000 {
            let thousands = english(number / 1000) + " thousand"
            let remainder = number % 1000
            guard remainder > 0 else {
                return thousands
            }
            return thousands + (remainder < 100 ? " and " : " ") + english(remainder)
        }
        
        if number >= 100 {
            let hundreds = units[number / 100] + " hundred"
            let remainder = number % 100
            return remainder > 0 ? hundreds + " and " + english(remainder) : hundreds
        }
        
        if number >= 20 {
            let ones = number % 10
            return ones > 0 ? tens[number / 10] + "-" + units[ones] : tens[number / 10]
        }
        
        return units[number]
    }
}
