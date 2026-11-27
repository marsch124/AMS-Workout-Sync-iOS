import SwiftUI
import WorkoutCore

/*
 * Block intro (round 30, pick 18): on Today for the first three days of a
 * block, a card "New block: Build 1" with what it is for, what will feel
 * different and one thing to watch, and a "Got it" button. Whether he has put
 * it away follows him on the shelf (coach/blockintro/<first day of the block>).
 * Any block can be read again by tapping its name under the season bars, or
 * from the row "This block" on a session page. Nothing here touches the plan.
 */

enum CoachBlocks {
    /* The plan's weeks as the block reading needs them: the book's own, else made from the sessions' phases. */
    @MainActor static func weeks(_ store: Store) -> [BlockWeek] {
        guard let view = store.view else { return [] }
        var planWeeks = store.book?.weeks ?? []
        if planWeeks.isEmpty {
            let mondays = Set(view.plan.map { PlanView.weekStart($0.dayKey) }).sorted()
            planWeeks = mondays.enumerated().map { i, monday in
                let phase = view.plan.first { PlanView.weekStart($0.dayKey) == monday && !$0.phase.isEmpty }?.phase ?? ""
                return PlanWeek(number: i + 1, monday: monday, phase: phase, tag: "")
            }
        }
        return planWeeks.map { BlockWeek(monday: $0.monday, phase: $0.phase, isEasy: $0.isEasy && !$0.isTest) }
    }

    @MainActor static func raceDay(_ store: Store) -> String? {
        guard let view = store.view, let road = Stats.road(view.visible, today: store.today, mapping: view.mapping), road.isRace else { return nil }
        return road.raceDay
    }

    @MainActor static func block(_ store: Store, on day: String) -> BlockSpan? {
        BlockIntro.block(on: day, weeks: weeks(store), raceDay: raceDay(store))
    }

    /* The block a picture switch asks for: AMSWS_BLOCK_INTRO=build|base|peak|taper|raceWeek|postSeason|easyWeek (DEBUG only). */
    static func debugBlock(today: String) -> BlockSpan? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["AMSWS_BLOCK_INTRO"] ?? ProcessInfo.processInfo.environment["AMSWS_BLOCK_CARD"] else { return nil }
        let kind = BlockKind(rawValue: raw) ?? .build
        let name: String
        switch kind {
        case .base: name = "Base 1"
        case .build: name = "Build 1"
        case .peak: name = "Peak"
        case .taper: name = "Taper"
        case .raceWeek: name = "Race week"
        case .postSeason: name = "Post-season"
        case .easyWeek: name = "Easy week"
        }
        return BlockSpan(kind: kind, name: name, first: today, last: PlanView.addDays(today, 6))
        #else
        return nil
        #endif
    }
}

/* The three lines, each in its own colour. */
struct BlockIntroLines: View {
    let kind: BlockKind

    var body: some View {
        let t = BlockIntro.text(kind)
        VStack(spacing: 8) {
            line("WHAT IT IS FOR", t.forIt, CoachHue.all[0], "block-intro-for")
            line("WHAT WILL FEEL DIFFERENT", t.different, CoachHue.all[1], "block-intro-different")
            line("ONE THING TO WATCH", t.watch, CoachHue.all[2], "block-intro-watch")
        }
    }

    private func line(_ name: String, _ text: String, _ hue: CoachHue, _ id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
            Text(text).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/* On Today, for the first three days of a block, until it is put away. */
struct BlockIntroCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        let today = store.today
        if let block = CoachBlocks.debugBlock(today: today) ?? CoachBlocks.block(store, on: today),
           BlockIntro.isShowing(on: today, block: block, seen: shelf.value(Bool.self, for: BlockIntro.shelfKey(first: block.first)) == true) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEW BLOCK").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                    Text(block.name).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("block-intro-title")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.season.deepHead)

                VStack(spacing: 10) {
                    BlockIntroLines(kind: block.kind)
                    Button {
                        _ = shelf.set(true, for: BlockIntro.shelfKey(first: block.first))
                    } label: {
                        Text("Got it").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.season.deepHead)
                    .accessibilityIdentifier("block-intro-got-it")
                }
                .padding(12)
                .background(Theme.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("block-intro-card")
        }
    }
}

/* The same lines on a sheet, to read again any time (no "Got it": nothing to put away). */
struct BlockIntroSheet: View {
    let block: BlockSpan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLOCK").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                        Text(block.name).font(.title2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.season.deepHead))
                    BlockIntroLines(kind: block.kind)
                }
                .padding(16).readableWidth(680)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("block-sheet-done")
                }
            }
        }
        .accessibilityIdentifier("block-intro-sheet")
    }
}

/* The name of a block under the season bars: a tap reads what it is for. */
struct BlockNameTap: ViewModifier {
    let phase: String
    @State private var open: BlockSpan?

    func body(content: Content) -> some View {
        if let kind = BlockIntro.kind(ofPhase: phase) {
            content
                .contentShape(Rectangle().inset(by: -6))
                .onTapGesture {
                    open = BlockSpan(kind: kind, name: BlockIntro.shortName(phase), first: "", last: "")
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("season-block-" + BlockIntro.shortName(phase).lowercased().replacingOccurrences(of: " ", with: "-"))
                .sheet(item: $open) { BlockIntroSheet(block: $0) }
        } else {
            content
        }
    }
}

extension View {
    func coachBlockTap(phase: String) -> some View { modifier(BlockNameTap(phase: phase)) }
}
