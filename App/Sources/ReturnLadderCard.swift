import SwiftUI
import WorkoutCore

/*
 * The way back after illness, drawn as a staircase while a return is running.
 * The steps are the rule book's own (ReturnLadder, from RuleBook.ladderStep):
 * rest, two easy days, week 1, week 2, back on the plan. The step he is on is
 * filled; the steps done carry the tick (done, as everywhere); the steps ahead
 * are pale (still to do, as everywhere). Nothing here changes his plan.
 */
struct ReturnLadderCard: View {
    @ObservedObject private var keeper = SuggestionKeeper.shared
    /* On Today the card follows the grey ladder line; on the illness page it is shown whenever a return runs. */
    var onToday = false
    /* The page spaces its rows this far apart; an empty card takes none of it. */
    var gap: CGFloat = 14

    var body: some View {
        let stairs = current()
        if stairs.isEmpty {
            Color.clear.frame(height: 0).padding(.top, -gap).accessibilityHidden(true)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("THE WAY BACK")
                    .font(.caption.weight(.bold)).tracking(0.8)
                    .foregroundStyle(Theme.today)
                ForEach(stairs) { stair in
                    row(stair)
                        .padding(.leading, CGFloat(stair.number - 1) * 12)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("return-ladder")
        }
    }

    private func current() -> [ReturnLadder.Stair] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_LADDER"] != nil {
            // Invented: ill nine days ago, symptom-free three days ago, so today is step 2 (the two easy days).
            let today = keeper.today
            let h = RBHealthTaps(illSince: PlanView.addDays(today, -9), illness: .belowNeck,
                                 symptomFreeSince: PlanView.addDays(today, -3))
            return ReturnLadder.stairs(health: h, settings: RuleBookSettings(), today: today)
        }
        #endif
        guard keeper.readable else { return [] }
        if onToday {
            let step = keeper.ladder.step
            guard keeper.ladderStatus != nil || step == .back else { return [] }
        }
        return ReturnLadder.stairs(health: keeper.keep.health, settings: keeper.keep.settings, today: keeper.today)
    }

    private func when(_ s: ReturnLadder.Stair) -> String {
        if !s.from.isEmpty, !s.to.isEmpty { return Dates.short(s.from) + " \u{2013} " + Dates.short(s.to) }
        if !s.from.isEmpty { return "From " + Dates.short(s.from) }
        if let d = s.days { return d == 1 ? "1 day" : "\(d) days" }
        return ""
    }

    private func row(_ s: ReturnLadder.Stair) -> some View {
        let isNow = s.state == .current
        let ink = isNow ? Color.white : Theme.text
        let sub = isNow ? Color.white.opacity(0.9) : Theme.secondary
        return HStack(alignment: .top, spacing: 8) {
            if s.state == .done {
                ZStack {
                    Circle().fill(Theme.today)
                    Glyph(name: "icon-check", size: 9).foregroundStyle(Color.white)
                }
                .frame(width: 16, height: 16).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text([when(s), s.title].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.footnote.weight(.semibold)).foregroundStyle(ink)
                Text(s.words).font(.caption).foregroundStyle(sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isNow ? Theme.today : (s.state == .done ? Theme.today.opacity(0.14) : Theme.today.opacity(0.07))))
        .opacity(s.state == .ahead ? 0.75 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("return-step-\(s.number)")
    }
}
