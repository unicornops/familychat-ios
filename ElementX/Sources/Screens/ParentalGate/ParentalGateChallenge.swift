//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// An adult-level question for the parental gate (unicornops/family-chat#232 decision 10).
///
/// Numbers are always written in words so that a child who can only recognise digits can't copy the
/// answer from the question, and the ranges are chosen to need an adult's reading or mental arithmetic
/// without being annoying: "Type the number six hundred and forty-seven in digits" or
/// "What is thirteen times seven?". The answer is always typed in digits.
nonisolated struct ParentalGateChallenge: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Type the number, given in words, in digits.
        case typeNumber(Int)
        /// Multiply two numbers given in words.
        case multiply(Int, Int)
    }
    
    /// Always three digits with a hyphenated tens part, e.g. "six hundred and forty-seven".
    static let hundredsRange = 1...9
    static let tensRange = 2...9
    static let onesRange = 1...9
    /// Two-digit by one-digit mental arithmetic, skipping the trivial ten times table.
    static let multiplicandRange = 6...19
    static let multiplierRange = 3...9
    
    /// The question strings are only in English (`Untranslated.strings`), so the number words are English
    /// too. When the questions get translated, pass the UI language here instead and
    /// ``ParentalGateNumberWords/words(for:locale:)`` switches to Foundation's spell-out rules.
    static let wordsLocale = Locale(identifier: "en_GB")
    
    let kind: Kind
    
    var answer: Int {
        switch kind {
        case .typeNumber(let number):
            number
        case .multiply(let multiplicand, let multiplier):
            multiplicand * multiplier
        }
    }
    
    var question: String {
        switch kind {
        case .typeNumber(let number):
            UntranslatedL10n.screenParentalGateQuestionTypeNumber(Self.words(number))
        case .multiply(let multiplicand, let multiplier):
            UntranslatedL10n.screenParentalGateQuestionMultiply(Self.words(multiplicand), Self.words(multiplier))
        }
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
            let kind: Kind = if Bool.random(using: &generator) {
                .typeNumber(randomNumberToType(using: &generator))
            } else {
                .multiply(randomMultiplicand(using: &generator), Int.random(in: multiplierRange, using: &generator))
            }
            let candidate = ParentalGateChallenge(kind: kind)
            
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
    
    private static func randomNumberToType(using generator: inout some RandomNumberGenerator) -> Int {
        let hundreds = Int.random(in: hundredsRange, using: &generator)
        let tens = Int.random(in: tensRange, using: &generator)
        let ones = Int.random(in: onesRange, using: &generator)
        return hundreds * 100 + tens * 10 + ones
    }
    
    private static func randomMultiplicand(using generator: inout some RandomNumberGenerator) -> Int {
        while true {
            let multiplicand = Int.random(in: multiplicandRange, using: &generator)
            if multiplicand != 10 {
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
