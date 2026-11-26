import SwiftUI
import WorkoutCore

/*
 * 2.9 lane "health": the Sleep debt, Weight, Energy and Water cards and their reader.
 * Four small reads (the week's sleep with Garmin's need, 90 days of weigh-ins and his goal, today's summary with calories and water),
 * kept in garmin-health.json with the half-hour rule. Shown only: nothing here advises, and nothing is written to Garmin.
 */
struct HealthFile: Codable {
    var lastTried: Date?
    var day: String?
    var nights: [BodyHealth.Night] = []
    var weight = BodyHealth.WeightTrend()
    var facts = BodyHealth.DayFacts()
}

extension GarminClient {
    func health(day: String) async throws -> HealthFile {
        var f = HealthFile()
        f.day = day
        let sleep = try await tolerant("/sleep-service/sleep/dailySleepSummariesByDate",
                                       ["startDate": GarminMorning.addDays(day, -6), "endDate": day])
        let range = try await tolerant("/weight-service/weight/range/\(GarminMorning.addDays(day, -90))/\(day)", ["includeAll": "true"])
        let goal = try await tolerant("/goal-service/goal/user/effective/weightgoal/\(GarminMorning.addDays(day, -365))/\(day)")
        let summary = try await tolerant("/usersummary-service/v2/dailysummaries", ["startDate": GarminMorning.addDays(day, -1), "endDate": day])
        f.nights = BodyHealth.nights(sleep, endingOn: day)
        f.weight = BodyHealth.weightTrend(range: range, goal: goal)
        f.facts = BodyHealth.dayFacts(summary, day: day)
        return f
    }
}

@MainActor
final class BodyHealthReader: ObservableObject {
    static let shared = BodyHealthReader()

    @Published private(set) var file = HealthFile()
    @Published private(set) var reading = false
    private var keySaved: Bool { GarminKey.isSaved }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-health.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(HealthFile.self, from: data) { file = f }
        #if DEBUG
        if GarminKey.isFake {
            file = Self.invented(day: ProcessInfo.processInfo.environment["AMSWS_TODAY"] ?? GarminMorning.dayKey(Date()))
        }
        #endif
    }

    /* What the cards show: only while a key is saved. */
    var shown: HealthFile? { keySaved ? file : nil }

    func readIfDue(today: String) async {
        guard keySaved, !GarminKey.isFake, GarminMorning.mayRead(lastTried: file.lastTried, now: Date()) else { return }
        await read(today: today)
    }

    func read(today: String) async {
        guard keySaved, !GarminKey.isFake, !reading else { return }
        reading = true
        let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] != nil ? today : GarminMorning.dayKey(Date())
        let tried = Date()
        do {
            var fresh = try await GarminClient.shared.health(day: day)
            fresh.lastTried = tried
            // A read that found nothing never replaces what is held.
            if fresh.weight.points.isEmpty { fresh.weight = file.weight }
            file = fresh
        } catch {
            file.lastTried = tried
        }
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: Self.fileURL, options: .atomic) }
        reading = false
    }

    #if DEBUG
    /* Invented, for pictures. AMSWS_BODY_NO_WATER=1 leaves the water unlogged. */
    static func invented(day: String) -> HealthFile {
        var f = HealthFile()
        f.day = day
        let slept: [Double?] = [6.8, 7.4, nil, 7.2, 8.0, 6.6, 7.3]
        let need = [480.0, 480, 460, 500, 480, 460, 480]
        f.nights = (0..<7).map { BodyHealth.Night(day: GarminMorning.addDays(day, $0 - 6), sleptMinutes: slept[$0].map { $0 * 60 }, needMinutes: need[$0]) }
        f.weight.points = stride(from: 88, through: 1, by: -3).map { k in
            BodyHealth.Weighing(day: GarminMorning.addDays(day, -k), kg: 72.0 + Double((k * 7) % 5) / 10 - Double(k) / 300)
        }
        f.weight.goalKg = 78
        let noWater = ProcessInfo.processInfo.environment["AMSWS_BODY_NO_WATER"] != nil
        f.facts = BodyHealth.DayFacts(energy: .init(total: 2480, active: 520, resting: 1960),
                                      water: .init(ml: noWater ? 0 : 1250, goalMl: 3000))
        return f
    }
    #endif
}

// MARK: Shared pieces

private struct HealthSheet: View {
    /* 2.10: the card's own colour (BodyHues.swift). */
    @Environment(\.bodyHue) private var hue
    let title: String
    let rows: [(String, String)]
    let note: String
    let id: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack(spacing: 10) {
                            Text(row.0).foregroundStyle(Theme.secondary).frame(width: 112, alignment: .leading)
                            Text(row.1).fontWeight(row.1 == "no reading" ? .regular : .semibold)
                                .foregroundStyle(row.1 == "no reading" ? Theme.secondary : Theme.text)
                            Spacer(minLength: 0)
                        }
                        .font(.body).padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("\(id)-row-\(i)")
                        if i < rows.count - 1 { Divider() }
                    }
                    Text(note).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
            }
            .background(hue.tile.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("\(id)-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(hue.accent)
    }
}

/* The card's frame: Body's tile fill, name in small capitals, figure with its unit beside it, one grey line. */
private struct HealthFace<Extra: View>: View {
    /* 2.10: the card's own colour (BodyHues.swift). */
    @Environment(\.bodyHue) private var hue
    let name: String
    let figure: String?
    let unit: String
    let line: String
    var lines = 1
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name.uppercased())
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let figure {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(figure).font(.title2.weight(.bold))
                    if !unit.isEmpty { Text(unit).font(.footnote.weight(.semibold)) }
                }
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(line).font(.caption).foregroundStyle(Theme.secondary).lineLimit(lines).minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            extra().padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
        .contentShape(Rectangle())
    }
}

private let noKeyLine = "Add your Garmin key in Settings to fill this."

#if DEBUG
private func debugSheet(_ name: String) -> Bool { ProcessInfo.processInfo.environment["AMSWS_BODY_SHEET"] == name }
#else
private func debugSheet(_ name: String) -> Bool { false }
#endif

// MARK: Sleep debt

/* Seven nights as slim round bars; each night's need stands behind its bar as a thin grey outline. A night without the watch has the small grey dash. */
private struct NightBars: View {
    /* 2.10: the card's own colour (BodyHues.swift). */
    @Environment(\.bodyHue) private var hue
    let nights: [BodyHealth.Night]
    var height: CGFloat = 46

    var body: some View {
        let top = max(60, nights.map { max($0.needMinutes, $0.sleptMinutes ?? 0) }.max() ?? 60)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(nights.enumerated()), id: \.offset) { i, n in
                let last = i == nights.count - 1
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: height)
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(Theme.secondary.opacity(0.45), lineWidth: 1)
                            .frame(height: max(6, height * CGFloat(n.needMinutes / top)))
                        if let s = n.sleptMinutes {
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(hue.accent)
                                .frame(height: max(4, height * CGFloat(s / top)))
                        } else {
                            Text("\u{2013}").font(.caption2).foregroundStyle(Theme.secondary)
                        }
                    }
                    Text(String(Dates.short(n.day).prefix(1)))
                        .font(.caption2.weight(last ? .heavy : .regular))
                        .foregroundStyle(last ? Theme.today : Theme.secondary).frame(height: 13)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct SleepDebtCard: View {
    let day: String
    @ObservedObject private var reader = BodyHealthReader.shared
    @State private var open = debugSheet("sleep-debt")

    var body: some View {
        let nights = reader.shown?.nights ?? []
        let balance = BodyHealth.balance(nights)
        Button { open = true } label: {
            if reader.shown == nil {
                HealthFace(name: "Sleep debt", figure: nil, unit: "", line: noKeyLine) { EmptyView() }
            } else if let balance {
                HealthFace(name: "Sleep debt", figure: BodyHealth.balanceFigure(balance), unit: "7 nights",
                           line: BodyHealth.sleepLine(nights) + ". Tap for each night.", lines: 2) { NightBars(nights: nights) }
            } else {
                HealthFace(name: "Sleep debt", figure: nil, unit: "",
                           line: "No nights recorded this week. The watch fills this once it has slept with you.") { EmptyView() }
            }
        }
        .buttonStyle(.plain)
        .disabled(balance == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(balance, nights))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("body-sleep-debt")
        .sheet(isPresented: $open) {
            HealthSheet(title: "Sleep debt \u{00B7} last 7 nights",
                        rows: nights.reversed().map { n in
                            (Dates.short(n.day), n.sleptMinutes.map { "\(formatDuration($0 * 60)) of \(formatDuration(n.needMinutes * 60))" } ?? "no reading")
                        },
                        note: "Sleep and naps against the need Garmin gives for each night (8h where it gives none). A night without the watch is left out.",
                        id: "body-sleep-debt-sheet")
        }
    }

    private func label(_ b: Double?, _ nights: [BodyHealth.Night]) -> String {
        guard let b else { return "Sleep debt. Nothing recorded this week." }
        return "Sleep debt \(BodyHealth.balanceFigure(b)) over 7 nights. \(BodyHealth.sleepLine(nights)). Opens each night."
    }
}

// MARK: Weight

private struct WeightLine: View {
    /* 2.10: the card's own colour (BodyHues.swift). */
    @Environment(\.bodyHue) private var hue
    let points: [BodyHealth.Weighing]
    var height: CGFloat = 46

    var body: some View {
        let kgs = points.map(\.kg)
        let lo = (kgs.min() ?? 0), hi = (kgs.max() ?? 1)
        let span = max(hi - lo, 0.5)
        let n = max(points.count - 1, 1)
        GeometryReader { g in
            let pos: (Int) -> CGPoint = { i in
                CGPoint(x: points.count == 1 ? g.size.width - 3 : 3 + (g.size.width - 6) * CGFloat(i) / CGFloat(n),
                        y: 3 + (g.size.height - 6) * CGFloat(1 - (points[i].kg - lo) / span))
            }
            ZStack {
                Path { p in
                    for i in points.indices { i == 0 ? p.move(to: pos(i)) : p.addLine(to: pos(i)) }
                }
                .stroke(hue.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = points.indices.last {
                    Circle().fill(hue.accent).frame(width: 7, height: 7).position(pos(last))
                }
            }
        }
        .frame(height: height)
    }
}

struct WeightCard: View {
    let day: String
    @ObservedObject private var reader = BodyHealthReader.shared
    @State private var open = debugSheet("weight")

    var body: some View {
        let trend = reader.shown?.weight
        let points = trend?.points ?? []
        Button { open = true } label: {
            if reader.shown == nil {
                HealthFace(name: "Weight", figure: nil, unit: "", line: noKeyLine) { EmptyView() }
            } else if let last = points.last {
                HealthFace(name: "Weight", figure: BodyHealth.kg(last.kg), unit: "kg",
                           line: BodyHealth.weightLine(dayWords: Dates.short(last.day), change: BodyHealth.weightChange(points), goalKg: trend?.goalKg)
                                 + ". Tap for each weigh-in.", lines: 2) {
                    if points.count > 1 { WeightLine(points: points) }
                }
            } else {
                HealthFace(name: "Weight", figure: nil, unit: "", line: BodyHealth.noWeighIns, lines: 2) { EmptyView() }
            }
        }
        .buttonStyle(.plain)
        .disabled(points.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(points.last.map { "Weight \(BodyHealth.kg($0.kg)) kg. Opens each weigh-in." } ?? "Weight. No weigh-ins in 90 days.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("body-weight")
        .sheet(isPresented: $open) {
            HealthSheet(title: "Weight \u{00B7} last 90 days",
                        rows: points.reversed().map { (Dates.short($0.day), BodyHealth.kg($0.kg) + " kg") },
                        note: "Every weigh-in Garmin holds for the last 90 days, newest first.", id: "body-weight-sheet")
        }
    }
}

// MARK: Energy and water

struct EnergyCard: View {
    let day: String
    @ObservedObject private var reader = BodyHealthReader.shared

    var body: some View {
        let e = reader.shown?.facts.energy
        HealthFace(name: "Energy", figure: e.map { BodyPage.grouped($0.total) }, unit: e == nil ? "" : "kcal",
                   line: reader.shown == nil ? noKeyLine
                       : e.map(BodyHealth.energyLine) ?? "No calories yet today. The watch sends them when it syncs.", lines: 2) { EmptyView() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(e.map { "Energy \(BodyPage.grouped($0.total)) kcal today. \(BodyHealth.energyLine($0))" } ?? "Energy. No calories yet today.")
            .accessibilityIdentifier("body-energy")
    }
}

struct WaterCard: View {
    /* 2.10: the card's own colour (BodyHues.swift). */
    @Environment(\.bodyHue) private var hue
    let day: String
    @ObservedObject private var reader = BodyHealthReader.shared

    var body: some View {
        let w = reader.shown?.facts.water
        HealthFace(name: "Water", figure: BodyHealth.waterFigure(w), unit: "ml",
                   line: reader.shown == nil ? noKeyLine : BodyHealth.waterLine(w), lines: 2) {
            if let f = BodyHealth.waterFill(w) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.secondary.opacity(0.2))
                        Capsule().fill(hue.accent).frame(width: max(6, g.size.width * CGFloat(f)))
                    }
                }
                .frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BodyHealth.waterFigure(w).map { "Water \($0) ml today. \(BodyHealth.waterLine(w))" } ?? "Water. \(BodyHealth.waterLine(w))")
        .accessibilityIdentifier("body-water")
    }
}
