//
// Copyright 2026 Unicorn Operations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Family Chat: text edit menus without the system items that leave the app ("Look Up", "Translate",
/// "Search Web"), which would otherwise bypass the parental gate. Use from a `UITextViewDelegate`'s
/// `textView(_:editMenuForTextIn:suggestedActions:)`.
enum ParentalGateEditMenu {
    /// Fragments of the selector or identifier names of the system items that leave the app.
    private static let exitNames = ["lookup", "define", "translate", "searchweb"]
    
    static func menu(from suggestedActions: [UIMenuElement]) -> UIMenu {
        UIMenu(children: filtered(suggestedActions))
    }
    
    static func filtered(_ elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap { element in
            switch element {
            case let menu as UIMenu:
                guard !isExit(menu.identifier.rawValue) else { return nil }
                return menu.replacingChildren(filtered(menu.children))
            case let command as UICommand:
                return isExit(NSStringFromSelector(command.action)) ? nil : command
            case let action as UIAction:
                return isExit(action.identifier.rawValue) ? nil : action
            default:
                return element
            }
        }
    }
    
    private static func isExit(_ name: String) -> Bool {
        let name = name.lowercased().replacingOccurrences(of: ":", with: "")
        return exitNames.contains { name.contains($0) }
    }
}
