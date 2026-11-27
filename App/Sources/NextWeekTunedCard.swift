import SwiftUI
import WorkoutCore

/*
 * Next week, tuned (round 30, his pick 2): on Sunday (once Sunday's sessions
 * are logged, or from 17:00) and on Monday until he answers, a card on Today
 * beside the Sunday card. Up to three changes, one line each, the reason
 * line, and two equal buttons: Take it · Keep my plan. One Undo for the card.
 * When nothing needs changing: one calm line, "Next week stays as planned".
 *
 * The rules are Core's (NextWeekTune); built-in Claude, when on, only picks
 * one of the rule book's choices and words the reason. His answer is on the
 * shelf ("tuning/week/<monday>"), so it follows him to every device. The plan
 * changes only by his tap, through Store.applySuggestion / undoSuggestion.
 */

/* Round 30 card colours (lane tuning). Each card has its own; the colour only tells the cards apart and means nothing else. */
struct TuneHue {
    /* The head card, with white words on it. */
    let fill: Color
    /* Names in small capitals, outlines. */
    let accent: Color
    /* The pale ground of its tiles. */
    let tile: Color

    /* Next week, tuned: indigo. */
    static let week = TuneHue(fill: .dynamic(light: 0x4F46E5, dark: 0x4338CA), accent: .dynamic(light: 0x4F46E5, dark: 0xA5B4FC),
                              tile: .dynamic(light: 0xECEBFD, dark: 0x22204A))
    /* Zones from your sessions: fuchsia. */
    static let zones = TuneHue(fill: .dynamic(light: 0xA21CAF, dark: 0x9D2BB5), accent: .dynamic(light: 0xA21CAF, dark: 0xF0ABFC),
                               tile: .dynamic(light: 0xF7E3F9, dark: 0x3E1846))
    /* Run power zones: gold. */
    static let power = TuneHue(fill: .dynamic(light: 0xA16207, dark: 0x92600A), accent: .dynamic(light: 0xA16207, dark: 0xFDE047),
                               tile: .dynamic(light: 0xF8F0DE, dark: 0x3F3212))
}

@MainActor
final class NextWeekTuner: ObservableObject {
    static let shared = NextWeekTuner()

    /* One calm grey line where the card was (a stale card, an Undo that could not be done). */
    @Published private(set) var notice: String?
    private var asking: Set<String> = []
    private var touched: Set<String> = []
    private var taking = false
    private var cache: (key: String, card: NextWeekTune.Card?)?

    static func answerKey(_ monday: String) -> String { "tuning/week/\(monday)" }
    static func claudeKey(_ monday: String) -> String { "tuning/week/\(monday)/claude" }

    enum Shown {
        case card(NextWeekTune.Card)
        case stays
        case changed(TuneAnswer, monday: String)
    }

    private var shelf: ShelfStore { ShelfStore.shared }

    // MARK: what Today shows

    func shown(store: Store) -> Shown? {
        #if DEBUG
        if let mode = debugMode { return debugShown(mode, store: store) }
        #endif
        guard store.canChangePlan, let book = store.book else { return nil }
        let today = store.today
        let settled = book.sessions.filter { $0.dayKey == today && $0.discipline.id != "rest" }.allSatisfy { $0.logged || $0.missed }
        let hour = Calendar.current.component(.hour, from: Date())
        guard let monday = NextWeekTune.anchor(today: today, hour: hour, sundaySettled: settled) else { return nil }
        return shown(monday: monday, store: store, input: SuggestionKeeper.shared.input(.afterSession))
    }

    private func shown(monday: String, store: Store, input: RuleBookInput?) -> Shown? {
        if let answer = shelf.value(TuneAnswer.self, for: Self.answerKey(monday)) {
            return answer.took && answer.on == store.today ? .changed(answer, monday: monday) : nil
        }
        if let book = store.book, NextWeekTune.takenInPlan(book.changes, monday: monday) { return nil }
        guard let card = card(monday: monday, store: store, input: input) else { return nil }
        if card.stays { return .stays }
        return .card(shelf.value(TuneClaude.self, for: Self.claudeKey(monday))?.apply(to: card) ?? card)
    }

    /* The rule book's card, worked out again only when the plan, the day, the mornings or the load change. */
    private func card(monday: String, store: Store, input: RuleBookInput?) -> NextWeekTune.Card? {
        guard let input else { return nil }
        let ratio = loadRatio(sunday: PlanView.addDays(monday, -1))
        let mornings = String(describing: input.feel.last(8, endingOn: PlanView.addDays(monday, -1)))
        let key = "\(store.bookVersion)|\(store.today)|\(monday)|\(mornings)|\(String(describing: ratio))|\(input.log.count)|\(String(describing: input.health))"
        if let cache, cache.key == key { return cache.card }
        let made = NextWeekTune.card(input, monday: monday, loadRatio: ratio)
        cache = (key, made)
        return made
    }

    /* Garmin's 7 days against 28 on that Sunday, when there is a key and a load file. */
    private func loadRatio(sunday: String) -> Double? {
        guard GarminKey.isSaved else { return nil }
        return BodyLoadReader.shared.summary(day: sunday).ratio
    }

    // MARK: his answer

    func take(_ card: NextWeekTune.Card, store: Store) {
        guard !taking else { return }
        taking = true
        defer { taking = false }
        let key = Self.answerKey(card.monday)
        if card.moves.isEmpty {
            // Only the invented picture card has no moves.
            shelf.set(TuneAnswer(took: true, on: store.today, lines: card.lines), for: key)
            return
        }
        guard let input = SuggestionKeeper.shared.input(.afterSession), NextWeekTune.stillFits(card, input: input) else {
            notice = SuggestionKeeper.staleWords
            return
        }
        let why = NextWeekTune.whyPrefixForPlan + card.lines.joined(separator: "; ")
        var logged = false
        let made = store.applySuggestion(card.moves, input: input, why: why) { ids in
            // His answer first: a plan changed by a card the shelf does not know of could be taken again.
            logged = ShelfStore.shared.set(TuneAnswer(took: true, on: store.today, lines: card.lines, changeIDs: ids), for: key)
            return logged
        }
        if made == nil, logged {
            // The plan could not be saved: the card is open again, as it was.
            shelf.remove(for: key)
        } else if made?.isEmpty == true {
            notice = SuggestionKeeper.staleWords
        }
    }

    func keep(_ card: NextWeekTune.Card, store: Store) {
        shelf.set(TuneAnswer(took: false, on: store.today), for: Self.answerKey(card.monday))
    }

    /* One Undo for the whole card: every change back, or none. The card is open again. */
    func undo(_ answer: TuneAnswer, monday: String, store: Store) {
        let key = Self.answerKey(monday)
        guard !answer.changeIDs.isEmpty else { shelf.remove(for: key); return }
        guard let book = store.book else { return }
        let live = SuggestionApply.liveIDs(answer.changeIDs, in: book)
        if live.isEmpty {
            shelf.remove(for: key)
            notice = SuggestionKeeper.goneWords
            return
        }
        guard live.count == answer.changeIDs.count, live.allSatisfy({ book.canUndo($0) }), store.undoSuggestion(answer.changeIDs) else {
            notice = SuggestionKeeper.changedAgainWords
            return
        }
        shelf.remove(for: key)
    }

    // MARK: Claude's pick

    func touched(_ monday: String) { touched.insert(monday) }

    /*
     * Once per menu, when Claude is on: Claude may pick one of the card's
     * choices (never anything else) and word the reason. The answer is kept on
     * the shelf and used only while the card is unanswered, untouched and its
     * menu the same; otherwise the rule book's own card stays.
     */
    func askClaude(_ card: NextWeekTune.Card) {
        guard !card.stays, !card.claudePicked, !card.choices.isEmpty else { return }
        let client = ClaudeClient.shared
        var on = client.isOn
        #if DEBUG
        if ClaudeKey.isFake { on = true }
        #endif
        let key = Self.claudeKey(card.monday), answerKey = Self.answerKey(card.monday)
        guard on, !asking.contains(key), !shelf.has(answerKey),
              shelf.value(TuneClaude.self, for: key)?.menu != card.menu,
              let input = SuggestionKeeper.shared.input(.afterSession) else { return }
        asking.insert(key)
        shelf.set(TuneClaude(menu: card.menu), for: key)
        let ask = NextWeekTune.claudeRequest(card, input: input)
        let body = ClaudePick.body(system: ask.system, user: ask.user)
        let n = card.choices.count
        let askedAt = Date()
        let monday = card.monday
        Task { @MainActor [weak self] in
            let run = await client.run(kind: "tune", label: NextWeekTune.title, detail: card.lines.joined(separator: "; "), body: body,
                                       fake: ClaudeAnswer(pick: min(2, n), why: "Why: a calmer week after the hard sessions suits the plan."),
                                       read: { ClaudePick.read($0, menuCount: n) })
            guard let self else { return }
            self.asking.remove(key)
            guard case .answer(let a) = run, a.pick >= 1,
                  ClaudePick.mayUse(askedAt: askedAt, now: Date(), touched: self.touched.contains(monday)),
                  !self.shelf.has(answerKey), self.shelf.value(TuneClaude.self, for: key)?.menu == card.menu else { return }
            self.shelf.set(TuneClaude(menu: card.menu, pick: a.pick, why: a.why), for: key)
        }
    }

    // MARK: pictures (DEBUG)

    #if DEBUG
    /* AMSWS_TUNED=card|stays|changed: the card whatever the day, for next week (the real engine on two invented tired mornings, else a fixed sample). */
    var debugMode: String? { ProcessInfo.processInfo.environment["AMSWS_TUNED"] }

    private func debugShown(_ mode: String, store: Store) -> Shown? {
        let monday = PlanView.addDays(PlanView.weekStart(store.today), 7)
        switch mode {
        case "stays": return .stays
        case "changed":
            return .changed(TuneAnswer(took: true, on: store.today, lines: Self.sample(monday).lines), monday: monday)
        default:
            var input = SuggestionKeeper.shared.input(.afterSession)
            input?.feel.set(.tired, on: PlanView.addDays(store.today, -1))
            input?.feel.set(.bad, on: PlanView.addDays(store.today, -2))
            if let answer = shelf.value(TuneAnswer.self, for: Self.answerKey(monday)) {
                return answer.took && answer.on == store.today ? .changed(answer, monday: monday) : nil
            }
            var made = Self.sample(monday)
            if let input, let real = NextWeekTune.card(input, monday: monday, loadRatio: nil), !real.stays { made = real }
            return .card(shelf.value(TuneClaude.self, for: Self.claudeKey(monday))?.apply(to: made) ?? made)
        }
    }

    static func sample(_ monday: String) -> NextWeekTune.Card {
        NextWeekTune.Card(monday: monday, kind: .easeMore,
                          choices: [NextWeekTune.Choice(moves: [], lines: ["Tue run: 60 \u{2192} 50 min", "Wed bike \u{2192} easy", "Thu run: 40 \u{2192} 35 min"])],
                          why: "Why: three sessions felt hard this week.", before: [])
    }
    #endif
}

// MARK: - on Today

/* Today, under the Sunday card: next week tuned, then the zones from your sessions. One hook in TodayView. */
struct TuningTodayCards: View {
    var body: some View {
        NextWeekTunedArea()
        StrongerZonesArea()
        // Takes no room (the page spaces its rows 14 apart); starts the Garmin read for the zones.
        TuningReader(spacing: 14)
    }
}

struct NextWeekTunedArea: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var tuner = NextWeekTuner.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var keeper = SuggestionKeeper.shared
    @ObservedObject private var diary = Diary.shared

    var body: some View {
        if let shown = tuner.shown(store: store) {
            switch shown {
            case .card(let card): NextWeekTunedView(card: card)
            case .stays:
                Text(NextWeekTune.staysLine)
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .accessibilityIdentifier("tuned-stays")
            case .changed(let answer, let monday): TunedChangedView(answer: answer, monday: monday)
            }
        }
        if let notice = tuner.notice {
            Text(notice)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tuned-notice")
        }
    }
}

struct NextWeekTunedView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var tuner = NextWeekTuner.shared
    @ObservedObject private var claude = ClaudeClient.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    let card: NextWeekTune.Card
    private let hue = TuneHue.week

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NextWeekTune.title.uppercased()).font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(card.lines.count)).font(.largeTitle.weight(.bold))
                    Text(card.lines.count == 1 ? "change to next week" : "changes to next week").font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.fill))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(card.lines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(.headline).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tuned-line-\(i)")
                }
                Text(card.why)
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tuned-why")
                if card.claudePicked {
                    Text("Picked by Claude from the rule book\u{2019}s choices")
                        .font(.caption).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("tuned-claude")
                } else if let trouble = claude.trouble {
                    Text(trouble.cardLine)
                        .font(.caption).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tuned-claude-trouble")
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    TuneEqualButton(title: RuleBookWords.takeIt, id: "tuned-take", tint: Theme.plan) { tuner.take(card, store: store) }
                    TuneEqualButton(title: RuleBookWords.keepMyPlan, id: "tuned-keep", tint: Theme.plan) { tuner.keep(card, store: store) }
                }
                .padding(.top, 2)
                Text(RuleBookWords.footer).font(.caption2).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        }
        // Any touch on the card: Claude's late answer may no longer change its words.
        .simultaneousGesture(TapGesture().onEnded { tuner.touched(card.monday) })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuned-card")
        .onAppear { tuner.askClaude(card) }
    }
}

/* "Changed — Undo" in the card's place until the day it was taken ends, with the lines it changed. */
struct TunedChangedView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var tuner = NextWeekTuner.shared
    let answer: TuneAnswer
    let monday: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(NextWeekTune.title.uppercased())
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(TuneHue.week.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Changed \u{2014}")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("tuned-changed")
                Button("Undo") { tuner.undo(answer, monday: monday, store: store) }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("tuned-undo")
                Spacer(minLength: 0)
            }
            ForEach(Array(answer.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TuneHue.week.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuned-changed-card")
    }
}

/* Two equal answers: same size, same outline, neither filled — as on the suggestion card. */
struct TuneEqualButton: View {
    let title: String
    let id: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/* No room taken (it gives back the page's own spacing); reads Garmin for the zones when due. */
struct TuningReader: View {
    @EnvironmentObject var store: Store
    let spacing: CGFloat

    var body: some View {
        Color.clear.frame(height: 0).padding(.top, -spacing)
            .accessibilityHidden(true)
            .task {
                SessionZonesKeeper.shared.attach(store)
                await SessionZonesKeeper.shared.readIfDue(today: store.today)
            }
    }
}
