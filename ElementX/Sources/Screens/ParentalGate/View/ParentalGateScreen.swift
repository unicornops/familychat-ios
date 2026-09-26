//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The parental gate: an adult-level question shown before any link leaves the app.
///
/// There is no timer. The question is plain text so VoiceOver reads it, it is re-announced when a wrong
/// answer replaces it, and everything scrolls so it works at every Dynamic Type size.
struct ParentalGateScreen: View {
    @Bindable var model: ParentalGateScreenModel
    
    @FocusState private var isAnswerFocused: Bool
    @AccessibilityFocusState private var isQuestionFocused: Bool
    
    var body: some View {
        ElementNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    question
                    answerForm
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.never)
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) {
                        model.cancel()
                    }
                    .accessibilityIdentifier("parentalGate-cancel")
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            isAnswerFocused = true
        }
        .onChange(of: model.challenge) { _, newChallenge in
            AccessibilityNotification.Announcement(UntranslatedL10n.screenParentalGateWrongAnswer + " " + newChallenge.question).post()
            isQuestionFocused = true
            isAnswerFocused = true
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UntranslatedL10n.screenParentalGateTitle)
                .font(.compound.headingMDBold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
            
            Text(UntranslatedL10n.screenParentalGateMessage)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
            
            if let destination = model.destination {
                Text(UntranslatedL10n.screenParentalGateDestination(destination))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            
            if let linkTextWarning = model.linkTextWarning {
                Text(linkTextWarning)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textCriticalPrimary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private var question: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.wrongAnswerCount > 0 {
                Text(UntranslatedL10n.screenParentalGateWrongAnswer)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textCriticalPrimary)
            }
            
            Text(model.challenge.question)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityFocused($isQuestionFocused)
                .accessibilityIdentifier("parentalGate-question")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private var answerForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            TextField(text: $model.answer) {
                Text(UntranslatedL10n.screenParentalGateAnswerPlaceholder)
                    .foregroundColor(.compound.textSecondary)
            }
            .focused($isAnswerFocused)
            .textFieldStyle(.compound(labelText: UntranslatedL10n.screenParentalGateAnswerLabel,
                                      accessibilityIdentifier: "parentalGate-answer"))
            .keyboardType(.numberPad)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .onSubmit(model.submit)
            
            Button(action: model.submit) {
                Text(L10n.actionContinue)
            }
            .buttonStyle(.compound(.primary))
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("parentalGate-continue")
        }
    }
}

// MARK: - Previews

struct ParentalGateScreen_Previews: PreviewProvider {
    static let model = ParentalGateScreenModel(destination: "https://safechat.family/privacy/",
                                               makeChallenge: { _ in .init(multiplicand: 23, multiplier: 7) },
                                               completion: { _ in })
    
    static var previews: some View {
        ParentalGateScreen(model: model)
    }
}
