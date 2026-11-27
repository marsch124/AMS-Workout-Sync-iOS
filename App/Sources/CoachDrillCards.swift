import SwiftUI
import WorkoutCore

/*
 * Drill cards (round 30, pick 16): each swim drill and each strength or
 * mobility exercise as a drawing, three numbered steps and one "What it trains"
 * line. Settings → Drill cards holds them all in a grid, each card in a colour
 * of its own; a session whose words name a drill or exercise gets a row
 * "Drill cards: Catch-up, Fist" that opens them. The drawings are drawn here
 * from the plain data in Core (DrillCards.swift): one even stroke of 1.9 on
 * the 24-point grid, scaled up, round ends and joins, no fill.
 *
 * Colours: each card has its own, never green (done), red (race, danger) or
 * teal. The colour only tells cards apart.
 */

struct CoachHue: Equatable {
    let accent: Color
    let tile: Color
    /* Behind white words, the same by day and night. */
    let fill: Color

    static let all: [CoachHue] = [
        CoachHue(accent: .dynamic(light: 0x2563EB, dark: 0x93C5FD), tile: .dynamic(light: 0xE3EBFC, dark: 0x1B2E59), fill: Color(hex: 0x2563EB)),   // blue
        CoachHue(accent: .dynamic(light: 0x7C3AED, dark: 0xC4B5FD), tile: .dynamic(light: 0xEEE5FD, dark: 0x352259), fill: Color(hex: 0x7C3AED)),   // purple
        CoachHue(accent: .dynamic(light: 0xD97706, dark: 0xFCD34D), tile: .dynamic(light: 0xFAEDDF, dark: 0x513414), fill: Color(hex: 0xB45309)),   // amber
        CoachHue(accent: .dynamic(light: 0xC026D3, dark: 0xF0ABFC), tile: .dynamic(light: 0xF7E3F9, dark: 0x4A1C52), fill: Color(hex: 0xA21CAF)),   // magenta
        CoachHue(accent: .dynamic(light: 0xEA580C, dark: 0xFDBA74), tile: .dynamic(light: 0xFCE9DF, dark: 0x562A16), fill: Color(hex: 0xC2410C)),   // orange
        CoachHue(accent: .dynamic(light: 0x4F46E5, dark: 0xA5B4FC), tile: .dynamic(light: 0xE8E7FC, dark: 0x282557), fill: Color(hex: 0x4338CA)),   // indigo
        CoachHue(accent: .dynamic(light: 0xDB2777, dark: 0xF9A8D4), tile: .dynamic(light: 0xFAE3ED, dark: 0x521C36), fill: Color(hex: 0xBE185D)),   // raspberry
        CoachHue(accent: .dynamic(light: 0x92400E, dark: 0xFDBA74), tile: .dynamic(light: 0xF3E8DD, dark: 0x4A2A12), fill: Color(hex: 0x92400E)),   // brown
        CoachHue(accent: .dynamic(light: 0x475569, dark: 0xCBD5E1), tile: .dynamic(light: 0xE6EAEF, dark: 0x2A3340), fill: Color(hex: 0x475569)),   // slate
    ]

    static func of(_ card: DrillCard) -> CoachHue {
        all[(DrillCards.all.firstIndex(of: card) ?? 0) % all.count]
    }
}

/* The drawing: lines, circles and the water, with the stroke scaled with the box. */
struct DrillDrawing: View {
    let art: DrillArt
    let colour: Color
    var water: Color = Theme.secondary.opacity(0.55)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / DrillArt.width, size.height / DrillArt.height)
            let ox = (size.width - DrillArt.width * s) / 2, oy = (size.height - DrillArt.height * s) / 2
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            let style = StrokeStyle(lineWidth: DrillArt.stroke * s, lineCap: .round, lineJoin: .round)
            for y in art.waves {
                var p = Path()
                var x = 0.0
                p.move(to: pt(0, y))
                while x <= DrillArt.width { p.addLine(to: pt(x, y + 0.6 * sin(x / 2.2))); x += 0.5 }
                ctx.stroke(p, with: .color(water), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round, lineJoin: .round))
            }
            for l in art.lines {
                var p = Path()
                p.move(to: pt(l[0], l[1]))
                for i in stride(from: 2, to: l.count, by: 2) { p.addLine(to: pt(l[i], l[i + 1])) }
                ctx.stroke(p, with: .color(colour), style: style)
            }
            for c in art.circles {
                let r = c[2] * s
                let p = Path(ellipseIn: CGRect(x: pt(c[0], c[1]).x - r, y: pt(c[0], c[1]).y - r, width: 2 * r, height: 2 * r))
                ctx.stroke(p, with: .color(colour), style: style)
            }
        }
        .aspectRatio(DrillArt.width / DrillArt.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/* One card in full: head filled with its colour, the drawing, three steps, what it trains. */
struct DrillCardBody: View {
    let card: DrillCard

    var body: some View {
        let hue = CoachHue.of(card)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.kind == .swim ? "SWIM DRILL" : (card.kind == .strength ? "STRENGTH" : "MOBILITY"))
                    .font(.caption.weight(.bold)).tracking(0.8).opacity(0.85)
                Text(card.name).font(.title2.weight(.bold))
                    .accessibilityIdentifier("drill-name")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hue.fill))

            DrillDrawing(art: card.drawing, colour: hue.accent)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Drawing of " + card.name)
                .accessibilityIdentifier("drill-drawing")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(card.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(i + 1)).font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(hue.fill))
                        Text(step).font(.body).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("drill-step-\(i + 1)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))

            VStack(alignment: .leading, spacing: 3) {
                Text("WHAT IT TRAINS").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
                Text(card.trains).font(.subheadline).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("drill-trains")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drill-card-\(card.id)")
    }
}

/* One card on its own page (opened from the grid). */
struct DrillCardPage: View {
    let card: DrillCard
    var body: some View {
        ScrollView {
            DrillCardBody(card: card).padding(16).readableWidth(680)
        }
        .background(CoachHue.of(card).tile.opacity(0.35).ignoresSafeArea())
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/* The page under Settings → Drill cards: every card in a grid, each its own colour. */
struct DrillCardsPage: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Drill cards").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.plan)
                    .accessibilityIdentifier("drill-cards-title")
                VStack(alignment: .leading, spacing: 2) {
                    Text("A DRAWING AND THREE STEPS").font(.caption.weight(.bold)).tracking(0.8).opacity(0.85)
                    Text("\(DrillCards.all.count) cards: swim drills, strength and mobility. Tap one to open it.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.plan.deepHead))

                NavigationLink { SwimCheckPage() } label: {
                    Text("Swim video check").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.plan.deepHead)
                .accessibilityIdentifier("drill-cards-swim-check")
                Text("Film one pool length and get three tips on your stroke.")
                    .font(.footnote).foregroundStyle(Theme.secondary)

                ForEach(DrillKind.allCases, id: \.self) { kind in
                    SectionHeading(text: kind == .swim ? "Swim drills" : (kind == .strength ? "Strength" : "Mobility"))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: sizeClass == .regular ? 3 : 2), spacing: 8) {
                        ForEach(DrillCards.cards(of: kind)) { card in
                            NavigationLink { DrillCardPage(card: card) } label: { DrillTile(card: card) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("drill-tile-\(card.id)")
                        }
                    }
                }
            }
            .padding(16)
            .readableWidth(760)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drill-cards-page")
    }
}

struct DrillTile: View {
    let card: DrillCard
    var body: some View {
        let hue = CoachHue.of(card)
        VStack(alignment: .leading, spacing: 4) {
            DrillDrawing(art: card.drawing, colour: hue.accent)
            Text(card.name.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(hue.accent)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
    }
}

/* Cards stacked on a sheet, for the row on a session page. */
struct DrillCardsSheet: View {
    let cards: [DrillCard]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(cards) { DrillCardBody(card: $0) }
                }
                .padding(16).readableWidth(680)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Drill cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("drill-sheet-done")
                }
            }
        }
        .accessibilityIdentifier("drill-cards-sheet")
    }
}

/*
 * Under a session's title: the drill cards its words name, the swim video check
 * on a swim session, and the block it belongs to. One hook in SessionView.
 */
struct CoachSessionRows: View {
    let workout: Workout
    @EnvironmentObject var store: Store
    @State private var showCards: [DrillCard]?
    @State private var showCheck = false
    @State private var showBlock: BlockSpan?
    @State private var showAll = false

    private var text: String {
        ([workout.title] + workout.sections.map(\.text)).joined(separator: " \n ")
    }

    var body: some View {
        let sport = workout.discipline.id
        let found = DrillCards.matches(in: text, discipline: sport)
        let general = found.isEmpty && sport == "swim" && DrillCards.mentionsDrillsInGeneral(text)
        let block = sport == "rest" ? nil : CoachBlocks.block(store, on: workout.dayKey)
        if !found.isEmpty || general || sport == "swim" || block != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !found.isEmpty {
                    Button { showCards = found } label: {
                        Text(DrillCards.rowWords(found)).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .settingsButton(tint: Theme.plan)
                    .accessibilityIdentifier("session-drill-cards")
                } else if general {
                    Button { showAll = true } label: { Text("Drill cards: swim drills") }
                        .settingsButton(tint: Theme.plan)
                        .accessibilityIdentifier("session-drill-cards")
                }
                if sport == "swim" {
                    Button("Swim video check") { showCheck = true }
                        .settingsButton(tint: Theme.plan)
                        .accessibilityIdentifier("session-swim-check")
                }
                if let block {
                    Button { showBlock = block } label: { Text("This block: " + block.name + " \u{2014} what it is for") }
                        .settingsButton(tint: Theme.season)
                        .accessibilityIdentifier("session-block-intro")
                }
            }
            .sheet(item: $showCards.asIdentifiable) { DrillCardsSheet(cards: $0.cards) }
            .sheet(isPresented: $showAll) { DrillCardsSheet(cards: DrillCards.cards(of: .swim)) }
            .sheet(isPresented: $showCheck) { NavigationStack { SwimCheckPage(inSheet: true) } }
            .sheet(item: $showBlock) { BlockIntroSheet(block: $0) }
        }
    }
}

private struct CardsBox: Identifiable { let id = UUID(); let cards: [DrillCard] }
private extension Binding where Value == [DrillCard]? {
    var asIdentifiable: Binding<CardsBox?> {
        Binding<CardsBox?>(get: { wrappedValue.map { CardsBox(cards: $0) } }, set: { if $0 == nil { wrappedValue = nil } })
    }
}
extension BlockSpan: Identifiable { public var id: String { first + name } }
