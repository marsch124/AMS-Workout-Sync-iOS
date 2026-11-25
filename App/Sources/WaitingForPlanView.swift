import SwiftUI
import WorkoutCore

/*
 * The iPad or the Mac opening Triathlon for the first time: no Excel, no
 * Dropbox, nothing to choose. The plan comes from iCloud, and until it does
 * this page says, in one line beside a coloured dot, what it is waiting for.
 * The dot never stands alone: the words say what it means.
 *
 * DEBUG: AMSWS_WAITING=off|working|none|excel|ready|update|problem shows one
 * state for a picture or a screen test.
 */
struct WaitingForPlanView: View {
    @EnvironmentObject var store: Store

    enum Shown: String {
        case off, working, none, excel, ready, update, problem
    }

    private var forced: Shown? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_WAITING"].flatMap(Shown.init(rawValue:))
        #else
        return nil
        #endif
    }

    var body: some View {
        let cloud = store.cloud
        let (shown, words, tint) = describe(forced, cloud.planState, cloud.status)
        VStack(spacing: 14) {
            Spacer(minLength: 80)
            Glyph(name: "icon-plan", size: 56).foregroundStyle(Theme.today)
            Text("Your training plan").font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                .accessibilityIdentifier("waiting-plan-title")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(tint).frame(width: 9, height: 9).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(words).font(.callout).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: 460, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("waiting-plan-" + Self.identifier(shown))
            Text(footnote(shown))
                .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    /* The six states of the design, plus a problem in words. */
    static func identifier(_ shown: Shown) -> String {
        switch shown {
        case .off: return "icloud-off"
        case .working: return "working"
        case .none: return "none"
        case .excel: return "excel"
        case .ready: return "ready"
        case .update: return "update"
        case .problem: return "problem"
        }
    }

    private func describe(_ forced: Shown?, _ state: PlanCloud.PlanState, _ status: SyncStatus) -> (Shown, String, Color) {
        let device = Device.isMac ? "Mac" : "iPad"
        let signIn = Device.isMac
            ? "Sign in to iCloud on this Mac (System Settings → your name → iCloud), then open Triathlon again."
            : "Sign in to iCloud on this \(device) (Settings → your name → iCloud), then open Triathlon again."
        let shown: Shown
        switch forced {
        case let f?: shown = f
        case nil:
            switch state {
            case .off: shown = .off
            case .unknown, .looking, .member: shown = status == .off ? .off : .working
            case .none: shown = .none
            case .excel: shown = .excel
            case .arrived: shown = .ready
            case .newer: shown = .update
            case .problem: shown = .problem
            }
        }
        switch shown {
        case .off:
            return (.off, signIn, Theme.secondary)
        case .working:
            var words = "Bringing your plan from iCloud…"
            if case .looking(let size?) = state, size > 0 {
                words += " " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            return (.working, words, Theme.extraHour)
        case .none:
            return (.none, "Your plan lives on your iPhone. Open Triathlon there once — it puts the plan in iCloud.", Theme.extraHour)
        case .excel:
            return (.excel, "Your plan still lives in Excel. On your iPhone: Settings → Your plan → Move the plan into this app.", Theme.extraHour)
        case .ready:
            if case .arrived(let sessions, let last, let from) = state {
                var words = "Plan from \(from) · \(sessions) sessions"
                if let last { words += " · last change " + Self.when(last) }
                return (.ready, words, Theme.today)
            }
            return (.ready, "Plan from your iPhone", Theme.today)
        case .update:
            return (.update, "Update Triathlon on this device", Theme.danger)
        case .problem:
            if case .problem(let why) = state { return (.problem, why, Theme.danger) }
            if case .problem(let why) = status { return (.problem, why, Theme.danger) }
            return (.problem, "iCloud could not be reached just now", Theme.danger)
        }
    }

    private func footnote(_ shown: Shown) -> String {
        switch shown {
        case .ready: return "Opening it now."
        case .update: return "This plan was saved by a newer Triathlon. Nothing here was changed. Update the app in TestFlight, then open it again."
        default: return "Your iPhone, iPad and Mac show the same plan once it is here. Nothing needs choosing on this \(Device.isMac ? "Mac" : "iPad")."
        }
    }

    /* "07:12" today, else "24 Nov 07:12". */
    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM HH:mm"
        return f.string(from: date)
    }
}
