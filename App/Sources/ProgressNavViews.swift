import SwiftUI
import WorkoutCore

/*
 * 2.20 (his pick "1 + 2 together", 27 Nov 2026: "make a sexy navigation area on the top of the Progress
 * page — it is getting complex"): eight colour tiles under the title, each with a live figure; tap one and
 * the page scrolls to that part. Once the tiles have scrolled away, a slim pinned row of the same colour
 * chips stays at the top; the chip of the part on screen is filled. Each part's first card carries a strip
 * of its colour along its top edge, so a part's start can be seen. Words and rules: Core `ProgressNav`.
 */

extension ProgressNav.Part {
    /* The tile and the filled chip: strong enough for white words, by day and by night. No teal (his word). */
    var tile: Color {
        switch self {
        case .race: return Color.dynamic(light: 0x7C3AED, dark: 0x6D28D9)    // purple
        case .fitness: return Color.dynamic(light: 0xDB2777, dark: 0xBE185D) // pink
        case .load: return Color.dynamic(light: 0x92400E, dark: 0x9A4A12)    // brown
        case .zones: return Color.dynamic(light: 0xDC2626, dark: 0xB91C1C)   // red
        case .routes: return Color.dynamic(light: 0x4338CA, dark: 0x4F46E5)  // indigo
        case .kept: return Color.dynamic(light: 0xA21CAF, dark: 0x9D1FA8)    // magenta
        case .bests: return Color.dynamic(light: 0xA16207, dark: 0xA16207)   // gold
        case .month: return Color.dynamic(light: 0x475569, dark: 0x52627A)   // slate
        }
    }

    /* The words of a pale chip. */
    var ink: Color {
        switch self {
        case .race: return Color.dynamic(light: 0x5B21B6, dark: 0xC4B5FD)
        case .fitness: return Color.dynamic(light: 0x9D174D, dark: 0xF9A8D4)
        case .load: return Color.dynamic(light: 0x78350F, dark: 0xFCD34D)
        case .zones: return Color.dynamic(light: 0x991B1B, dark: 0xFCA5A5)
        case .routes: return Color.dynamic(light: 0x3730A3, dark: 0xA5B4FC)
        case .kept: return Color.dynamic(light: 0x86198F, dark: 0xF0ABFC)
        case .bests: return Color.dynamic(light: 0x854D0E, dark: 0xFDE68A)
        case .month: return Color.dynamic(light: 0x334155, dark: 0xCBD5E1)
        }
    }
}

enum ProgressNavSpace {
    static let name = "progress-scroll"
}

/* Where each part's first card stands in the visible page, for the lit chip. */
struct ProgressPartTops: PreferenceKey {
    static var defaultValue: [ProgressNav.Part: CGFloat] = [:]
    static func reduce(value: inout [ProgressNav.Part: CGFloat], nextValue: () -> [ProgressNav.Part: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/* The bottom edge of the tiles in the visible page; far below while there are no tiles. */
struct ProgressTilesBottom: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

extension View {
    /*
     * Marks a part's first card: its colour along the top edge, where it stands (for the lit chip), and a
     * scroll target a little above it, so a jump leaves the card's heading clear of the pinned row.
     */
    func progressPart(_ part: ProgressNav.Part) -> some View {
        self
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                    .fill(part.tile)
                    .frame(height: 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: ProgressPartTops.self, value: [part: g.frame(in: .named(ProgressNavSpace.name)).minY])
                }
            }
            .background(alignment: .top) {
                // The target reaches 64 points above the card (negative padding moves it in the layout itself,
                // where the jump looks; an alignment guide did not, his heading hid under the row).
                Color.clear.frame(height: 65).id(part.anchor).padding(.top, -64)
            }
    }
}

struct ProgressTiles: View {
    let items: [(part: ProgressNav.Part, figure: String)]
    let columns: Int
    let jump: (ProgressNav.Part) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(items, id: \.part) { item in
                    Button { jump(item.part) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.part.name).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                            Text(item.figure).font(.headline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(item.part.tile))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.part.name), \(item.figure)")
                    .accessibilityHint("Jumps to this part")
                    .accessibilityIdentifier("progress-tile-" + item.part.rawValue)
                }
            }
            // The tap is not obvious on a tile: the screen says it (his rule, 19 Nov 2026).
            Text("Tap a tile to jump to that part").font(.caption).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress-tiles")
    }
}

struct ProgressChips: View {
    let parts: [ProgressNav.Part]
    let active: ProgressNav.Part?
    let width: CGFloat
    let jump: (ProgressNav.Part) -> Void

    var body: some View {
        ScrollViewReader { row in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(parts) { part in
                        let on = part == active
                        Button { jump(part) } label: {
                            Text(part.name).font(.subheadline.weight(.semibold))
                                .foregroundStyle(on ? Color.white : part.ink)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(on ? part.tile : part.tile.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                        .id(part)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("progress-chip-" + part.rawValue)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: width, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // The lit chip stays in view on a narrow phone.
            .onChange(of: active) { _, part in
                guard let part else { return }
                withAnimation(.easeOut(duration: 0.2)) { row.scrollTo(part, anchor: .center) }
            }
        }
        .background(Theme.bg.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress-chips")
    }
}
