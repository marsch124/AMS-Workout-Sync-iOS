import SwiftUI
import WorkoutCore

/*
 * 2.18 lane "score": "Session score" (a done session's zones against what the plan asked) and "Fitter at the same
 * pulse" (pace, power and speed at the pulse of zone 2, month by month). Shown only; nothing here reaches the plan.
 * Garmin is read through the existing client; numbers only are kept (never the key) in Application Support.
 * Picture switches: AMSWS_SCORE=on|hard|too (a done session, with AMSWS_DONE=run AMSWS_FAKE_GARMIN=1),
 * AMSWS_TAB=progress AMSWS_FAKE_GARMIN=1 (the card), plus AMSWS_FITTER_PAGE=1 (the page).
 */

// MARK: - reading

extension GarminClient {
    /* The season's runs and rides, up to eight small reads of 99 (Garmin's page size), newest first. */
    func seasonSteadyWorkouts(from: String, to: String) async throws -> [SteadyWorkout] {
        var out: [SteadyWorkout] = []
        var start = 0
        for _ in 0..<8 {
            let answer = try await tolerant("/activitylist-service/activities/search/activities",
                                            ["startDate": from, "endDate": to, "limit": "99", "start": String(start)])
            let count = SamePulse.pageCount(answer)
            out += SamePulse.parse(answer)
            if count < 99 { break }
            start += 99
        }
        return out
    }
}

@MainActor
final class SessionScoreReader: ObservableObject {
    static let shared = SessionScoreReader()

    struct Item { let key: String; let day: String; let sport: String; let seconds: Double? }

    /* Seconds in zones 1…5 by session key. Past sessions never change, so these are kept for good. */
    @Published private(set) var zones: [String: [Double]] = [:]
    private var tried: Set<String> = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-score.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode([String: [Double]].self, from: data) { zones = f }
    }

    func forget() { zones = [:]; tried = []; try? FileManager.default.removeItem(at: Self.fileURL) }

    func result(key: String, zone: Int) -> SessionScore.Result? {
        guard GarminKey.isSaved else { return nil }
        #if DEBUG
        if GarminKey.isFake { return SessionScore.score(zoneSeconds: Self.invented(key: key, zone: zone), plannedZone: zone) }
        #endif
        return zones[key].flatMap { SessionScore.score(zoneSeconds: $0, plannedZone: zone) }
    }

    /* One list read for all the days asked about; a session already held, or already tried this run, is not asked again. */
    func resolve(_ items: [Item]) async {
        guard GarminKey.isSaved, !GarminKey.isFake else { return }
        let wanted = items.filter { zones[$0.key] == nil && !tried.contains($0.key) }
        guard let first = wanted.map(\.day).min(), let last = wanted.map(\.day).max() else { return }
        wanted.forEach { tried.insert($0.key) }
        guard let list = try? await GarminClient.shared.activities(from: first, to: last) else { return }
        for item in wanted {
            if let found = GarminActivity.match(day: item.day, sport: item.sport, seconds: item.seconds, among: list), found.zoneSeconds.count == 5 {
                zones[item.key] = found.zoneSeconds
            }
        }
        if zones.count > 600 { zones = Dictionary(uniqueKeysWithValues: zones.sorted { $0.key > $1.key }.prefix(400).map { ($0.key, $0.value) }) }
        if let data = try? JSONEncoder().encode(zones) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    #if DEBUG
    /* An invented 45 minutes: AMSWS_SCORE=on|hard|too picks the word; without it the sessions differ by their key. */
    static func invented(key: String, zone: Int) -> [Double] {
        let mode = ProcessInfo.processInfo.environment["AMSWS_SCORE"] ?? ["on", "on", "hard", "too"][key.utf8.reduce(0, { $0 + Int($1) }) % 4]
        let total = 2700.0
        let above = zone >= 5 ? 0 : total * (mode == "too" ? 0.5 : mode == "hard" ? 0.25 : 0.04)
        let below = zone <= 1 ? 0 : (mode == "on" ? 300.0 : 120.0)
        var z = [Double](repeating: 0, count: 5)
        z[zone - 1] = total - above - below
        if zone < 5 { z[zone] = above }
        if zone > 1 { z[zone - 2] = below }
        return z
    }
    #endif
}

// MARK: - the session's page

struct SessionScoreBlock: View {
    @ObservedObject private var reader = SessionScoreReader.shared
    let workout: Workout
    let mapping: Mapping

    private var zone: Int? {
        guard SessionScore.isScored(sport: workout.discipline.id) else { return nil }
        if let z = SessionScore.plannedZone(intensity: workout.planned.intensity) { return z }
        #if DEBUG
        if GarminKey.isFake { return 2 }
        #endif
        return nil
    }

    var body: some View {
        Group {
            if let zone, let r = reader.result(key: workout.key, zone: zone) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.word.text).font(.headline).foregroundStyle(Theme.plan)
                        .accessibilityIdentifier("session-score-word")
                    Text(r.line).font(.footnote).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("session-score-line")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("session-score")
            }
        }
        .task(id: workout.key) {
            guard zone != nil else { return }
            await reader.resolve([.init(key: workout.key, day: workout.dayKey, sport: workout.discipline.id,
                                        seconds: Stats.actualSeconds(workout, mapping))])
        }
    }
}

// MARK: - Progress: the week's line and the card

struct ScoreProgressCards: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var score = SessionScoreReader.shared

    private var items: [(w: Workout, zone: Int)] {
        guard let mapping = store.mapping else { return [] }
        let monday = PlanView.weekStart(store.today), next = GarminMorning.addDays(monday, 7)
        return store.displayed.compactMap { w in
            guard w.dayKey >= monday, w.dayKey < next, w.state == .done, !w.missed, SessionScore.isScored(sport: w.discipline.id) else { return nil }
            var z = SessionScore.plannedZone(intensity: w.planned.intensity)
            #if DEBUG
            if z == nil, GarminKey.isFake { z = 2 }
            #endif
            _ = mapping
            return z.map { (w, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let line = SessionScore.weekLine(items.compactMap { score.result(key: $0.w.key, zone: $0.zone)?.word }) {
                Text(line).font(.footnote.weight(.semibold)).foregroundStyle(Theme.plan)
                    .accessibilityIdentifier("score-week-line")
            }
            FitterCard()
        }
        .task {
            guard let mapping = store.mapping else { return }
            await score.resolve(items.map { .init(key: $0.w.key, day: $0.w.dayKey, sport: $0.w.discipline.id, seconds: Stats.actualSeconds($0.w, mapping)) })
        }
    }
}

// MARK: - Fitter at the same pulse

private enum FitterHue {
    /* Rose, a clear magenta-pink so it is never read as race red (not purple, not green, not red, no teal). */
    static let fill = Color.dynamic(light: 0xC9279A, dark: 0x9C2380)
    static let accent = Color.dynamic(light: 0xC9279A, dark: 0xF3A6DC)
    static let tile = Color.dynamic(light: 0xFBE3F3, dark: 0x4D1A40)
    static let ground = Color.dynamic(light: 0xFEF0FA, dark: 0x2A1228)
}

private struct FitterFile: Codable { var lastTried: Date?; var season: String?; var list: [SteadyWorkout] = [] }

@MainActor
final class SamePulseReader: ObservableObject {
    static let shared = SamePulseReader()
    @Published private(set) var list: [SteadyWorkout] = []
    private var file = FitterFile()

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-fitter.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(FitterFile.self, from: data) { file = f; list = f.list }
    }

    func forget() { file = FitterFile(); list = []; try? FileManager.default.removeItem(at: Self.fileURL) }

    func shown(today: String) -> [SteadyWorkout] {
        #if DEBUG
        if GarminKey.isFake { return Self.invented(today: today) }
        #endif
        return GarminKey.isSaved ? list : []
    }

    /* At most one read in 30 minutes, from 1 September. */
    func readIfDue(today: String) async {
        guard GarminKey.isSaved, !GarminKey.isFake, GarminMorning.mayRead(lastTried: file.lastTried, now: Date()), let first = SamePulse.months(today: today).first else { return }
        file.lastTried = Date()
        do {
            let fresh = try await GarminClient.shared.seasonSteadyWorkouts(from: first + "-01", to: today)
            // An empty answer never replaces a season already held.
            if !fresh.isEmpty || file.season != first { file.list = fresh; file.season = first; list = fresh }
        } catch {}
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    #if DEBUG
    /* Invented: three steady runs and rides a month, getting a little quicker; the second month has one ride only. */
    static func invented(today: String) -> [SteadyWorkout] {
        var out: [SteadyWorkout] = []
        for (i, m) in SamePulse.months(today: today).enumerated() {
            for d in 0..<3 {
                let day = m + String(format: "-%02d", 4 + d * 7)
                out.append(SteadyWorkout(sport: "run", day: day, seconds: 2700 + Double(d) * 300, avgHr: 136 + Double(d), speedMps: 2.78 + Double(i) * 0.07 + Double(d) * 0.01, powerW: 205 + Double(i) * 6))
                if i == 1 && d > 0 { continue }
                out.append(SteadyWorkout(sport: "bike", day: day, seconds: 3600, avgHr: 134 + Double(d), speedMps: 7.4 + Double(i) * 0.15, powerW: nil))
            }
        }
        return out
    }
    #endif
}

private struct FitterData {
    let run: [SamePulseMonth]
    let ride: [SamePulseMonth]
    var any: Bool { run.contains { $0.enough } || ride.contains { $0.enough } }

    static func make(list: [SteadyWorkout], zones: Zones?, today: String) -> FitterData? {
        var band = SamePulse.zone2Band(zones)
        #if DEBUG
        if band == nil, GarminKey.isFake { band = 130...145 }
        #endif
        guard let band else { return nil }
        return FitterData(run: SamePulse.byMonth(list, sport: "run", band: band, today: today),
                          ride: SamePulse.byMonth(list, sport: "bike", band: band, today: today))
    }
}

/* One slim round bar per month: the figure right beside the month, the bar after it. A month with too few shows "—". */
private struct MonthBars: View {
    let months: [SamePulseMonth]
    let sport: String
    let id: String
    let ink: Color
    let track: Color
    let bar: Color

    private func figure(_ m: SamePulseMonth) -> String {
        guard let s = m.speedMps else { return "—" }
        let base = sport == "run" ? SamePulse.paceText(s) : SamePulse.speedText(s)
        return m.powerW.map { base + " · \(Int($0.rounded())) W" } ?? base
    }

    private func fraction(_ s: Double) -> CGFloat {
        let all = months.compactMap(\.speedMps)
        guard let top = all.max(), top > 0 else { return 0 }
        // A quicker month has the longer bar; the scale starts at three quarters of the quickest, so small gains stay visible.
        return max(0.06, CGFloat((s / top - 0.75) / 0.25))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(months, id: \.month) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(SamePulse.shortMonth(m.month)).font(.footnote.weight(.bold)).foregroundStyle(ink).frame(width: 32, alignment: .leading)
                        Text(figure(m)).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(ink)
                        if !m.enough {
                            Text("too few steady \(sport == "run" ? "runs" : "rides")").font(.caption).foregroundStyle(ink.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(track)
                            if let s = m.speedMps { Capsule().fill(bar).frame(width: geo.size.width * fraction(s)) }
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fitter-month-\(id)-\(m.month)")
            }
        }
    }
}

struct FitterCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = SamePulseReader.shared
    @State private var open = false

    var body: some View {
        Group {
            if GarminKey.isSaved {
                let data = FitterData.make(list: reader.shown(today: store.today), zones: store.zones, today: store.today)
                Button { open = true } label: { card(data) }
                    .buttonStyle(.plain)
                    .navigationDestination(isPresented: $open) { FitterPage(data: data) }
            }
        }
        .task { await reader.readIfDue(today: store.today) }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["AMSWS_FITTER_PAGE"] != nil { open = true } }
        #endif
    }

    private func card(_ data: FitterData?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FITTER AT THE SAME PULSE").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
            if let data, data.any {
                if let l = SamePulse.line(sport: "run", months: data.run) {
                    Text(l).font(.subheadline.weight(.semibold)).foregroundStyle(.white).accessibilityIdentifier("fitter-line-run")
                }
                if let l = SamePulse.line(sport: "bike", months: data.ride) {
                    Text(l).font(.subheadline.weight(.semibold)).foregroundStyle(.white).accessibilityIdentifier("fitter-line-ride")
                }
                MonthBars(months: data.run.contains { $0.enough } ? data.run : data.ride, sport: data.run.contains { $0.enough } ? "run" : "bike",
                          id: data.run.contains { $0.enough } ? "run" : "ride", ink: .white, track: .white.opacity(0.25), bar: .white)
                    .padding(.top, 4)
            } else {
                Text(data == nil ? "Your pace at the same pulse shows once your zones are in the plan."
                                 : "Not enough steady runs or rides at your zone 2 pulse yet.")
                    .font(.subheadline).foregroundStyle(.white)
            }
            Text("Tap for run and ride side by side").font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FitterHue.fill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fitter-card")
    }
}

private struct FitterPage: View {
    let data: FitterData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Fitter at the same pulse").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.progress).padding(.top, 8)
                    .accessibilityIdentifier("fitter-title")
                if let data, data.any {
                    HStack(alignment: .top, spacing: 12) {
                        tile("RUN", months: data.run, sport: "run", id: "run")
                        tile("RIDE", months: data.ride, sport: "bike", id: "ride")
                    }
                } else {
                    Text("Not enough steady runs or rides at your zone 2 pulse yet.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Text("How it is worked out: from Garmin's summary of each run or ride of 20 minutes or more whose average pulse sits inside your zone 2 pulse band. For each month, the middle value of those. A month with fewer than two of them shows a dash. Nothing here changes your plan.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fitter-how")
            }
            .padding(.horizontal, 16).padding(.bottom, 32)
            .readableWidth(820)
        }
        .background(FitterHue.ground.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("fitter-page")
    }

    private func tile(_ name: String, months: [SamePulseMonth], sport: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(FitterHue.accent)
            Text(sport == "run" ? "Pace and power" : "Speed").font(.caption).foregroundStyle(Theme.secondary)
            MonthBars(months: months, sport: sport, id: id, ink: Theme.text, track: FitterHue.accent.opacity(0.18), bar: FitterHue.accent)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FitterHue.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fitter-tile-\(id)")
    }
}
