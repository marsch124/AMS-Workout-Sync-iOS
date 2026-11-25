import SwiftUI
import UIKit
import WorkoutCore

/*
 * Round 28, "system": the keys of the wide layout (iPad with a keyboard, and the Mac).
 * ⌘1…⌘6 already live on the side list's rows. Added here: ⌘N, ← →, ⌘T, ⌘F, ? and ⌘/, and the "Keys" plate that
 * lists every key. Space = Done as planned sits on that button itself (SessionView) and Esc is Cancel on every
 * page where something is changed. Keys without a modifier never act while a text field has the focus.
 */

/* Who has the keyboard right now: true when a text box is being typed in. */
enum TypingNow {
    private final class Finder: NSObject {
        static weak var found: UIResponder?
    }

    @MainActor static var active: Bool {
        Finder.found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.noteAsFirstResponder), to: nil, from: nil, for: nil)
        return Finder.found is UITextInput
    }

    fileprivate static func note(_ r: UIResponder) { Finder.found = r }
}

extension UIResponder {
    @objc fileprivate func noteAsFirstResponder() { TypingNow.note(self) }
}

/* ⌘F: the page's search box, found by its identifier `session-search`; nothing happens where there is none. */
enum SearchFocus {
    @MainActor @discardableResult static func focus() -> Bool {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows }.flatMap { $0 }
        for window in windows {
            if let field = find(in: window) { return field.becomeFirstResponder() }
        }
        return false
    }

    private static func find(in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == "session-search" {
            return textInput(in: view)
        }
        for sub in view.subviews { if let hit = find(in: sub) { return hit } }
        return nil
    }

    private static func textInput(in view: UIView) -> UIView? {
        if view is UITextInput, view.canBecomeFirstResponder { return view }
        for sub in view.subviews { if let hit = textInput(in: sub) { return hit } }
        return nil
    }
}

/*
 * The keys, as buttons nobody sees: each carries its shortcut, so the hold-⌘ list (and the Mac's) names it.
 * Every action is told to the wide root, which owns the page, the week and the month.
 */
struct WideKeys: View {
    let newSession: () -> Void
    let step: (Int) -> Void
    let today: () -> Void
    let focusSearch: () -> Void
    let showKeys: () -> Void

    var body: some View {
        ZStack {
            Button("New session", action: newSession).keyboardShortcut("n", modifiers: .command)
            Button("Jump to today", action: today).keyboardShortcut("t", modifiers: .command)
            Button("Search sessions", action: focusSearch).keyboardShortcut("f", modifiers: .command)
            Button("Show the keys", action: showKeys).keyboardShortcut("/", modifiers: .command)
            Button("Show the keys") { if !TypingNow.active { showKeys() } }.keyboardShortcut("?", modifiers: [])
            Button("Earlier week or month") { if !TypingNow.active { step(-1) } }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Later week or month") { if !TypingNow.active { step(1) } }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/* The Keys plate: a head card in Settings' slate, then one tile per key with the key beside its action. */
struct KeysPlate: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keys")
                        .font(.title2.weight(.bold))
                    Text("For an iPad with a keyboard, and the Mac. Hold \u{2318} on an iPad to see them too.")
                        .font(.footnote)
                        .opacity(0.9)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.settingsFill))

                ForEach(Array(KeyGuide.rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.keys)
                            .font(.callout.weight(.bold).monospaced())
                            .foregroundStyle(Theme.settings)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.settings.opacity(0.16)))
                            .fixedSize()
                            .frame(minWidth: 112, alignment: .leading)
                        Text(row.action)
                            .font(.callout).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.settings.opacity(0.10)))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("keys-row-\(index)")
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .tint(Theme.mainButton)
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .accessibilityIdentifier("keys-done")
            }
            .padding(14)
        }
        .background(Theme.settings.opacity(0.06).background(Theme.bg).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keys-plate")
    }
}
