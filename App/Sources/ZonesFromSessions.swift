import SwiftUI
import Combine
import WorkoutCore

/*
 * Zones that keep up (round 30, his pick 3): "New zones offered between tests
 * when your sessions show you got stronger. Uses your run power too."
 *
 * The app reads the last 6 weeks of Garmin sessions (the activity list, then
 * each run, ride and pool swim's laps once — from the recorded file, or
 * Garmin's split list), keeps one small estimate per session (numbers only,
 * Application Support, tuning-zones.json) and, when two sessions point clearly
 * higher than the zones in use, shows a card on Today and on Your zones:
 * "Your sessions point to stronger zones", old → new for each, and the
 * sessions it came from. "Use the new zones" records a test entry marked
 * "From your sessions" (so Tests on Progress shows it) and sets the run
 * threshold power; one Undo takes both back. "Keep mine" puts the offer away
 * until sessions show clearly more. Zones are never lowered.
 *
 * Shelf keys (follow him to every device): "tuning/run-power",
 * "tuning/zones-taken", "tuning/zones-kept", "tuning/zones-undone".
 */
@MainActor
final class SessionZonesKeeper: ObservableObject {
    static let shared = SessionZonesKeeper()

    static let runPowerKey = "tuning/run-power"
    static let takenKey = "tuning/zones-taken"
    static let keptKey = "tuning/zones-kept"
    static let undoneKey = "tuning/zones-undone"
    /* At most this many recorded sessions are fetched in one read; the next visit goes on. */
    static let perRead = 8

    @Published private(set) var samples: [SessionZones.Sample] = []
    @Published private(set) var notice: String?

    private struct SamplesFile: Codable {
        var lastTried: Date?
        var samples: [SessionZones.Sample] = []
        /* Activities already read, whether or not they gave an estimate: never fetched twice. */
        var tried: [Int] = []
    }

    private var file = SamplesFile()
    private var reading = false
    private var cleaning = false
    private weak var store: Store?
    private var bag: Set<AnyCancellable> = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tuning-zones.json")
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_RESET"] != nil { try? FileManager.default.removeItem(at: Self.fileURL) }
        #endif
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(SamplesFile.self, from: data) {
            file = f
            samples = f.samples
        }
    }

    private var shelf: ShelfStore { ShelfStore.shared }

    /* Once, from Today or Your zones: an entry taken back on one device is taken out here too when the plans meet. */
    func attach(_ store: Store) {
        guard self.store !== store else { return }
        self.store = store
        store.$book
            .sink { [weak self] _ in DispatchQueue.main.async { self?.cleanUp() } }
            .store(in: &bag)
    }

    private func cleanUp() {
        guard !cleaning, let store, store.canChangePlan else { return }
        let undone = shelf.value([String].self, for: Self.undoneKey) ?? []
        guard !undone.isEmpty else { return }
        let kept = SessionZones.removing(undone, from: store.tests)
        guard kept != store.tests else { return }
        cleaning = true
        defer { cleaning = false }
        store.replaceTests(kept)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    // MARK: reading Garmin

    /* At most once in 30 minutes, only with a key: the last 6 weeks' list, then the laps of sessions not yet read. */
    func readIfDue(today: String) async {
        #if DEBUG
        if debugMode != nil || GarminKey.isFake { return }
        #endif
        guard GarminKey.isSaved, !reading, GarminMorning.mayRead(lastTried: file.lastTried, now: Date()) else { return }
        reading = true
        defer { reading = false }
        file.lastTried = Date()
        do {
            let list = try await GarminClient.shared.activities(from: PlanView.addDays(today, -SessionZones.lookBackDays), to: today)
            var fetched = 0
            for a in list where SessionZones.sport(ofGarmin: a.typeKey) != nil && !file.tried.contains(a.id) {
                let laps: [GarminLap]
                if let held = Self.heldLaps(a.id) {
                    laps = held
                } else {
                    guard fetched < Self.perRead else { break }
                    fetched += 1
                    laps = try await GarminClient.shared.recording(activityId: a.id).laps
                }
                file.tried.append(a.id)
                if let s = SessionZones.sample(activityId: a.id, day: a.day, typeKey: a.typeKey, seconds: a.seconds, laps: laps) {
                    file.samples.removeAll { $0.activityId == s.activityId }
                    file.samples.append(s)
                }
            }
            // More to read: the next visit goes on at once.
            if fetched >= Self.perRead { file.lastTried = nil }
        } catch {
            // No key, no connection or an odd answer: what is held stays, nothing is shown from a guess.
        }
        let from = PlanView.addDays(today, -SessionZones.lookBackDays - 7)
        file.samples.removeAll { $0.day < from }
        file.tried = Array(file.tried.suffix(600))
        samples = file.samples
        save()
    }

    /* A session whose page was opened already has its laps on this device (GarminActivityReader's file). */
    private static func heldLaps(_ id: Int) -> [GarminLap]? {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("garmin-activities", isDirectory: true).appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: url), let d = try? JSONDecoder().decode(GarminActivityDetail.self, from: data),
              !d.recording.laps.isEmpty else { return nil }
        return d.recording.laps
    }

    // MARK: what is in use, what is offered

    var runPower: RunPowerSetting? {
        #if DEBUG
        if debugMode == "power" { return shelf.value(RunPowerSetting.self, for: Self.runPowerKey) ?? RunPowerSetting(watts: 250, day: PlanView.todayKey()) }
        #endif
        return shelf.value(RunPowerSetting.self, for: Self.runPowerKey)
    }

    func inUse(_ store: Store) -> SessionZones.InUse {
        let now = ZoneMaths.current(store.tests)
        var use = SessionZones.InUse(lthr: now.lthr ?? store.zones?.lthr, css: now.css, runPower: runPower?.watts)
        #if DEBUG
        if debugMode != nil { use.lthr = use.lthr ?? 160; use.css = use.css ?? 112 }
        #endif
        return use
    }

    /* "Changed — Undo" shows until the end of the day it was taken. */
    func takenToday(_ store: Store) -> ZonesTaken? {
        #if DEBUG
        if debugMode == "changed" {
            return ZonesTaken(day: store.today, entryName: nil, runPowerBefore: nil, tookRunPower: false,
                              lines: ["Threshold pulse 160 \u{2192} 164 bpm", "Run power none yet \u{2192} 258 W"])
        }
        #endif
        guard let t = shelf.value(ZonesTaken.self, for: Self.takenKey), t.day == store.today else { return nil }
        return t
    }

    /* The offer, when the plan lives here and nothing was taken today. */
    func proposal(_ store: Store) -> SessionZones.Proposal? {
        var held = samples
        #if DEBUG
        if debugMode != nil {
            if debugMode == "power" { return nil }
            held = Self.invented(today: store.today, inUse: inUse(store))
        }
        #endif
        guard store.canChangePlan, takenToday(store) == nil else { return nil }
        let p = SessionZones.proposal(held, inUse: inUse(store), today: store.today)
        return SessionZones.shown(p, kept: shelf.value(SessionZones.Kept.self, for: Self.keptKey), today: store.today)
    }

    static func line(_ r: SessionZones.Row) -> String { "\(r.measure.title) \(r.figure) \(r.measure.unit)" }

    // MARK: his answer

    func use(_ p: SessionZones.Proposal, store: Store) {
        notice = nil
        let undone = shelf.value([String].self, for: Self.undoneKey) ?? []
        let entry = SessionZones.entry(p, tests: store.tests, today: store.today, used: undone)
        if let entry {
            guard store.replaceTests(SessionZones.inserting(entry, into: store.tests)) else {
                notice = "That could not be saved. Your zones are as they were."
                return
            }
        }
        let before = shelf.value(RunPowerSetting.self, for: Self.runPowerKey)
        var tookPower = false
        if let w = p.row(.runPower)?.new {
            tookPower = shelf.set(RunPowerSetting(watts: w, day: store.today), for: Self.runPowerKey)
        }
        shelf.set(ZonesTaken(day: store.today, entryName: entry?.name, runPowerBefore: before, tookRunPower: tookPower,
                             lines: p.rows.map(Self.line)), for: Self.takenKey)
    }

    func keepMine(_ p: SessionZones.Proposal, store: Store) {
        notice = nil
        shelf.set(SessionZones.Kept(p, day: store.today), for: Self.keptKey)
    }

    /* One Undo: the test entry out (on every device, by its name) and the run power back. */
    func undo(store: Store) {
        notice = nil
        guard let t = takenToday(store) else { return }
        #if DEBUG
        if debugMode == "changed" { return }
        #endif
        if let name = t.entryName {
            var undone = shelf.value([String].self, for: Self.undoneKey) ?? []
            if !undone.contains(name) { undone.append(name) }
            shelf.set(Array(undone.suffix(50)), for: Self.undoneKey)
            let kept = SessionZones.removing([name], from: store.tests)
            if kept != store.tests, !store.replaceTests(kept) {
                notice = "That could not be saved. Your zones are as they were."
                return
            }
        }
        if t.tookRunPower {
            if let b = t.runPowerBefore { shelf.set(b, for: Self.runPowerKey) } else { shelf.remove(for: Self.runPowerKey) }
        }
        shelf.remove(for: Self.takenKey)
    }

    // MARK: pictures (DEBUG)

    #if DEBUG
    /* AMSWS_ZONES_SESSIONS=card|changed|power: the card from invented sessions, its "Changed — Undo", or the run power zones (250 W, invented). */
    var debugMode: String? { ProcessInfo.processInfo.environment["AMSWS_ZONES_SESSIONS"] }

    static func invented(today: String, inUse: SessionZones.InUse) -> [SessionZones.Sample] {
        let lthr = inUse.lthr ?? 160, css = inUse.css ?? 112
        return [
            SessionZones.Sample(activityId: 9001, day: PlanView.addDays(today, -3), sport: "run", pulse: lthr + 5.2, power: 262, powerPulse: lthr),
            SessionZones.Sample(activityId: 9002, day: PlanView.addDays(today, -10), sport: "bike", pulse: lthr + 4.1),
            SessionZones.Sample(activityId: 9003, day: PlanView.addDays(today, -17), sport: "run", pulse: lthr + 1.0, power: 258, powerPulse: lthr - 2),
            SessionZones.Sample(activityId: 9004, day: PlanView.addDays(today, -5), sport: "swim", swimPace: css - 4),
            SessionZones.Sample(activityId: 9005, day: PlanView.addDays(today, -12), sport: "swim", swimPace: css - 3),
        ]
    }
    #endif
}

// MARK: - the card (Today and Your zones)

struct StrongerZonesArea: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var keeper = SessionZonesKeeper.shared
    @ObservedObject private var shelf = ShelfStore.shared

    var body: some View {
        if let t = keeper.takenToday(store) {
            ZonesChangedView(taken: t)
        } else if let p = keeper.proposal(store) {
            StrongerZonesCard(proposal: p)
        }
        if let notice = keeper.notice {
            Text(notice)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("zones-sessions-notice")
        }
    }
}

struct StrongerZonesCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    let proposal: SessionZones.Proposal
    private let hue = TuneHue.zones

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ZONES FROM YOUR SESSIONS").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
                Text("Your sessions point to stronger zones").font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("zones-sessions-title")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.fill))

            ForEach(proposal.rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.measure.title.uppercased())
                        .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(row.figure).font(.title2.weight(.bold))
                        Text(row.measure.unit).font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(SessionZones.sourcesLine(row.sessions, dayText: { Dates.short($0) }))
                        .font(.caption).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("zones-sessions-row-\(row.measure.rawValue)")
            }

            Text(useLine)
                .font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                TuneEqualButton(title: "Use the new zones", id: "zones-sessions-use", tint: hue.accent) {
                    SessionZonesKeeper.shared.use(proposal, store: store)
                }
                TuneEqualButton(title: "Keep mine", id: "zones-sessions-keep", tint: hue.accent) {
                    SessionZonesKeeper.shared.keepMine(proposal, store: store)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zones-sessions-card")
    }

    /* What "Use the new zones" does, said on the card itself. */
    private var useLine: String {
        var parts: [String] = []
        if proposal.row(.pulse) != nil || proposal.row(.swim) != nil {
            parts.append("Use the new zones adds \u{201C}\(SessionZones.entryName)\u{201D} to your tests; your zones follow it until your next test.")
        }
        if proposal.row(.runPower) != nil { parts.append("Run power targets then show beside your pulse on runs.") }
        return parts.joined(separator: " ")
    }
}

struct ZonesChangedView: View {
    @EnvironmentObject var store: Store
    let taken: ZonesTaken

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ZONES FROM YOUR SESSIONS")
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(TuneHue.zones.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Changed \u{2014}")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("zones-sessions-changed")
                Button("Undo") { SessionZonesKeeper.shared.undo(store: store) }
                    .settingsButton(tint: TuneHue.zones.accent)
                    .accessibilityIdentifier("zones-sessions-undo")
                Spacer(minLength: 0)
            }
            ForEach(Array(taken.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TuneHue.zones.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zones-sessions-changed-card")
    }
}

// MARK: - run power

/* Your zones: the card from your sessions, then the run power zones. One hook in ZonesView. */
struct ZonesFromSessionsSection: View {
    var body: some View {
        StrongerZonesArea()
        RunPowerZonesCard()
        TuningReader(spacing: 12)
    }
}

/* Run power zones from the run threshold power, as a tile card in its own colour. */
struct RunPowerZonesCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var keeper = SessionZonesKeeper.shared
    @ObservedObject private var shelf = ShelfStore.shared
    private let hue = TuneHue.power

    var body: some View {
        if let p = keeper.runPower {
            VStack(alignment: .leading, spacing: 6) {
                Text("RUN POWER ZONES").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(hue.accent)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(jsNumberString(p.watts.rounded())).font(.title2.weight(.bold))
                    Text("W threshold").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.text)
                Text(p.day.isEmpty ? SessionZones.mark : SessionZones.mark + ", " + Dates.short(p.day))
                    .font(.caption).foregroundStyle(Theme.secondary)
                ForEach(RunPowerZones.rows(p.watts), id: \.label) { row in
                    // The figure right beside its name, never at the far edge.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label).font(.body).foregroundStyle(Theme.text)
                        Text(row.value).font(.body.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("run-power-row")
                }
                Text("Each zone as a share of your run threshold power: up to 80 %, 81\u{2013}88, 89\u{2013}95, 96\u{2013}105, from 106 %. Shown beside the pulse on your runs.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("run-power-card")
        }
    }
}

/* On a run's page, beside the zone pill: the power the intensity names ("Power 203–220 W"). */
struct RunPowerPill: View {
    @ObservedObject private var keeper = SessionZonesKeeper.shared
    @ObservedObject private var shelf = ShelfStore.shared
    let workout: Workout

    var body: some View {
        if workout.discipline.id == "run", let p = keeper.runPower,
           let target = RunPowerZones.target(intensity: workout.planned.intensity, threshold: p.watts) {
            Pill(text: "Power " + target).accessibilityIdentifier("run-power-pill")
        }
    }
}

/* In the zone sheet a run's pill opens: the run power rows the intensity names. */
struct RunPowerSheetRows: View {
    @ObservedObject private var keeper = SessionZonesKeeper.shared
    @ObservedObject private var shelf = ShelfStore.shared
    let intensity: String
    let sport: String

    var body: some View {
        if sport == "run", let p = keeper.runPower {
            let zs = Zones.zones(in: intensity)
            let rows = RunPowerZones.rows(p.watts).filter { Zones.zoneNumber(of: $0.label).map(zs.contains) ?? false }
            if !rows.isEmpty {
                ZoneTableCard(table: ZoneTable(title: "RUN POWER", rows: rows))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("run-power-sheet")
            }
        }
    }
}
