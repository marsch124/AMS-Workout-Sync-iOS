import SwiftUI
import WorkoutCore

/*
 * Garmin's morning numbers: the line under Today's heading, and the small
 * plate a tap on it opens. Shown only — no judgement, no advice, and nothing
 * here reaches the plan. The trend sits in brackets beside each figure, green
 * the good way, red the other, grey within normal — the rule of the Health
 * line, so the two never read differently.
 */
enum GarminWords {
    /* 7.33 hours as "7 h 20". */
    static func sleep(_ hours: Double) -> String {
        // Written as every other length of time in the app: "7h 20m".
        formatDuration((hours * 60).rounded() * 60)
    }

    static func whole(_ v: Double) -> String { "\(Int(v.rounded()))" }

    /* How far from his own fortnight: "+3", "−2" or "±0", and which way is good. */
    static func delta(_ value: Double, _ normal: Double?, lowerIsBetter: Bool) -> (figure: String, colour: Color, spoken: String)? {
        guard let normal, normal > 0 else { return nil }
        let d = value - normal
        let n = Int(abs(d).rounded())
        let figure = n == 0 ? "±0" : (d > 0 ? "+" : "−") + "\(n)"
        guard abs(d) >= max(1, normal * 0.04) else { return (figure, Theme.secondary, "as usual") }
        let good = lowerIsBetter ? d < 0 : d > 0
        return (figure, good ? Theme.today : Theme.danger, "\(n) \(d > 0 ? "above" : "below") your normal")
    }

    static func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
}

/* The line on Today, with the dot and its words under it. Leaves itself out with no key or no number. */
struct GarminMorningRow: View {
    @ObservedObject private var reader = GarminReader.shared
    let today: String
    /* The Health line above it is missing: sit right under the heading as that line does. */
    var alone = false
    @State private var plate = false

    var body: some View {
        if let g = reader.shown {
            let fresh = GarminMorning.isFromThisMorning(g, today: today)
            VStack(alignment: .leading, spacing: 1) {
                // When the figures do not fit one line, the break falls between two of
                // them, so no line ends on a stray "·".
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(breaks(g).enumerated()), id: \.offset) { _, at in
                        line(g, breakBefore: at).fixedSize(horizontal: true, vertical: false)
                    }
                    line(g, breakBefore: 2).lineLimit(3).minimumScaleFactor(0.8)
                }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("morning-garmin")
                    .accessibilityLabel(spoken(g))
                    .accessibilityAddTraits(.isButton)
                HStack(spacing: 5) {
                    GarminDot(fresh: fresh)
                    Text(GarminWords.caption(g, fresh: fresh)).font(.caption2).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("morning-dot")
            }
            .padding(.top, alone ? -9 : 0)
            .contentShape(Rectangle())
            .onTapGesture { plate = true }
            .sheet(isPresented: $plate) {
                MorningNumbersView(numbers: g, today: today)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func name(_ s: String) -> Text { Text(s).foregroundStyle(Theme.secondary) }
    private func value(_ s: String) -> Text { Text(s).fontWeight(.bold).foregroundStyle(Theme.text) }

    private func bracket(_ f: MorningNumbers.Figure, lowerIsBetter: Bool) -> Text {
        // The trend is always in brackets, so a missing one never looks like a fault.
        guard let d = GarminWords.delta(f.value, f.normal, lowerIsBetter: lowerIsBetter) else {
            let left = max(1, Fortnight.daysNeeded - f.days)
            return Text(" (" + (left == 1 ? "normal tomorrow" : "normal in \(left) days") + ")").foregroundStyle(Theme.secondary)
        }
        return Text("\u{00A0}(\(d.figure))").foregroundStyle(d.colour)
    }

    /* Where the line may break: nowhere first, then before the last figure, then earlier. */
    private func breaks(_ g: MorningNumbers) -> [Int] {
        let n = parts(g).count
        return [n] + stride(from: n - 1, to: 0, by: -1).map { $0 }
    }

    private func line(_ g: MorningNumbers, breakBefore: Int) -> Text {
        let parts = parts(g)
        guard var out = parts.first else { return Text("") }
        for (i, part) in parts.enumerated().dropFirst() {
            out = out + (i == breakBefore ? Text("\n") : Text(" · ").foregroundStyle(Theme.secondary)) + part
        }
        return out
    }

    private func parts(_ g: MorningNumbers) -> [Text] {
        var parts: [Text] = []
        if let f = g.hrv { parts.append(name("HRV\u{00A0}") + value(GarminWords.whole(f.value)) + bracket(f, lowerIsBetter: false)) }
        if let f = g.sleepHours { parts.append(name("Sleep\u{00A0}") + value(GarminWords.sleep(f.value).replacingOccurrences(of: " ", with: "\u{00A0}"))) }
        if let f = g.resting { parts.append(name("Resting\u{00A0}") + value(GarminWords.whole(f.value)) + bracket(f, lowerIsBetter: true)) }
        if let f = g.bodyBattery { parts.append(name("Body\u{00A0}Battery\u{00A0}") + value(GarminWords.whole(f.value))) }
        return parts
    }

    private func spoken(_ g: MorningNumbers) -> String {
        var out: [String] = []
        func say(_ label: String, _ f: MorningNumbers.Figure, _ text: String, lowerIsBetter: Bool?) {
            var s = "\(label) \(text)"
            if let lowerIsBetter, let d = GarminWords.delta(f.value, f.normal, lowerIsBetter: lowerIsBetter) { s += ", " + d.spoken }
            out.append(s)
        }
        if let f = g.hrv { say("HRV", f, GarminWords.whole(f.value), lowerIsBetter: false) }
        if let f = g.sleepHours { say("Sleep", f, GarminWords.sleep(f.value), lowerIsBetter: nil) }
        if let f = g.resting { say("Resting heart rate", f, GarminWords.whole(f.value), lowerIsBetter: true) }
        if let f = g.bodyBattery { say("Body Battery", f, GarminWords.whole(f.value), lowerIsBetter: nil) }
        return out.joined(separator: ". ") + ". " + GarminWords.caption(g, fresh: GarminMorning.isFromThisMorning(g, today: today))
    }
}

extension GarminWords {
    /* What the dot says, in words: always beside the dot, never the dot alone. */
    static func caption(_ g: MorningNumbers, fresh: Bool) -> String {
        if fresh { return "Garmin · this morning, read \(time(g.readAt))" }
        return "Garmin · older numbers from \(Dates.short(g.day))"
    }
}

/* Green: from this morning. Grey: older. */
struct GarminDot: View {
    let fresh: Bool
    var body: some View {
        Circle().fill(fresh ? Theme.today : Theme.secondary.opacity(0.7)).frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/* The plate: every number with its own fortnight, and when it was read. */
struct MorningNumbersView: View {
    let numbers: MorningNumbers
    let today: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fresh = GarminMorning.isFromThisMorning(numbers, today: today)
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Garmin, this morning").font(.title3.weight(.bold)).foregroundStyle(Theme.today)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    GarminDot(fresh: fresh)
                    Text(fresh ? "From this morning · read \(GarminWords.time(numbers.readAt)) from Garmin"
                               : "Older numbers from \(Dates.short(numbers.day)) · read \(GarminWords.time(numbers.readAt)) from Garmin")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("morning-plate-dot")

                row("hrv", "HRV overnight", numbers.hrv, text: { "\(GarminWords.whole($0)) ms" }, lowerIsBetter: false,
                    extra: numbers.hrvRangeLow.flatMap { low in numbers.hrvRangeHigh.map { "Garmin's balanced range \(low)–\($0)" } })
                row("sleep", "Sleep last night", numbers.sleepHours, text: GarminWords.sleep, lowerIsBetter: nil,
                    normalText: GarminWords.sleep)
                row("resting", "Resting heart rate", numbers.resting, text: { "\(GarminWords.whole($0)) bpm" }, lowerIsBetter: true)
                row("bodybattery", "Body Battery on waking", numbers.bodyBattery, text: { GarminWords.whole($0) }, lowerIsBetter: nil)
                row("stress", "Stress yesterday", numbers.stress, text: { GarminWords.whole($0) }, lowerIsBetter: nil)

                if let synced = numbers.watchSynced {
                    Text("Your watch last sent its numbers to Garmin at \(GarminWords.time(synced)).")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Text("Shown only. These numbers never change your plan.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityIdentifier("morning-plate")
        // Done at the top right, as on every other sheet.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("morning-plate-done")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        }
    }

    /* One number: its name with the figure right beside it, and under it the normal. */
    private func row(_ id: String, _ title: String, _ f: MorningNumbers.Figure?, text: (Double) -> String,
                     lowerIsBetter: Bool?, normalText: ((Double) -> String)? = nil, extra: String? = nil) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
                    if let f {
                        Text(text(f.value)).font(.body.weight(.bold)).foregroundStyle(Theme.text)
                        if let lowerIsBetter, let d = GarminWords.delta(f.value, f.normal, lowerIsBetter: lowerIsBetter) {
                            Text("(\(d.figure))").font(.subheadline).foregroundStyle(d.colour)
                        }
                    } else {
                        Text("none yet").font(.body).foregroundStyle(Theme.secondary)
                    }
                }
                if let f {
                    Text(normalLine(f, normalText ?? { GarminWords.whole($0) }) + (extra.map { " · " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(Theme.secondary)
                } else {
                    Text("Garmin has not given this one yet.").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("morning-row-" + id)
    }

    private func normalLine(_ f: MorningNumbers.Figure, _ text: (Double) -> String) -> String {
        guard let n = f.normal else { return "No normal yet · \(f.days) of \(Fortnight.daysNeeded) days" }
        return "Normal \(text(n)) over \(f.days) days"
    }
}
