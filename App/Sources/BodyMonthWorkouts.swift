import SwiftUI
import WorkoutCore

/* 2.9 lane "workouts": every Garmin workout of the month, the plan's and the ones outside it. Shown only. */
extension GarminClient {
    /* The month's activities: one small read (limit 99). */
    func monthActivities(from: String, to: String) async throws -> [MonthWorkout] {
        let answer = try await tolerant("/activitylist-service/activities/search/activities",
                                        ["startDate": from, "endDate": to, "limit": "99", "start": "0"])
        return MonthWorkouts.parse(answer)
    }
}

private struct MonthWorkoutsFile: Codable {
    var lastTried: Date?
    var month: String?
    var list: [MonthWorkout] = []
}

@MainActor
final class MonthWorkoutsReader: ObservableObject {
    static let shared = MonthWorkoutsReader()
    @Published private(set) var list: [MonthWorkout] = []
    @Published private(set) var month = ""
    @Published private(set) var reading = false
    private var file = MonthWorkoutsFile()

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-month.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(MonthWorkoutsFile.self, from: data) {
            file = f
            list = f.list
            month = f.month ?? ""
        }
    }

    /* What the card shows for this day's month: only while a key is saved. */
    func shown(day: String) -> [MonthWorkout] {
        #if DEBUG
        if GarminKey.isFake { return Self.invented(day: day) }
        #endif
        guard GarminKey.isSaved, month == String(day.prefix(7)) else { return [] }
        return MonthWorkouts.ofMonth(list, day: day)
    }

    func readIfDue(today: String) async {
        guard GarminKey.isSaved, !GarminKey.isFake, GarminMorning.mayRead(lastTried: file.lastTried, now: Date()) else { return }
        await read(today: today)
    }

    func read(today: String) async {
        guard GarminKey.isSaved, !GarminKey.isFake, !reading else { return }
        reading = true
        file.lastTried = Date()
        do {
            let fresh = try await GarminClient.shared.monthActivities(from: MonthWorkouts.firstDay(of: today), to: today)
            let ofMonth = MonthWorkouts.ofMonth(fresh, day: today)
            // An empty answer never replaces a month already held.
            if !ofMonth.isEmpty || month != String(today.prefix(7)) {
                list = ofMonth
                month = String(today.prefix(7))
                file.list = ofMonth
                file.month = month
            }
        } catch {}
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: Self.fileURL, options: .atomic) }
        reading = false
    }

    #if DEBUG
    /* An invented month, no network: 9 workouts, the last two on the same day. */
    static func invented(day: String) -> [MonthWorkout] {
        let types = ["running", "lap_swimming", "cycling", "walking", "strength_training", "hiking", "running", "breathwork", "indoor_cycling"]
        let names = ["Sample Run", "Sample Swim", "Sample Ride", "Sample Walk", "Sample Strength", "Sample Hike", "Sample Easy Run", "Sample Breathing", "Sample Trainer"]
        let end = Int(day.suffix(2)) ?? 1
        let month = String(day.prefix(7))
        var out: [MonthWorkout] = []
        for i in 0..<types.count {
            let d = max(1, end - (types.count - 1 - i) / 2)
            let key = String(format: "%@-%02d", month, d)
            let hour = i % 2 == 0 ? 7 : 18
            let time = String(format: "%02d:%02d", hour, 10 + i)
            guard let date = GarminMorning.date(key) else { continue }
            let start = GarminMorning.calendar().date(bySettingHour: hour, minute: 10 + i, second: 0, of: date) ?? date
            let walky = types[i] == "walking" || types[i] == "hiking"
            out.append(MonthWorkout(id: "9000\(i)", name: names[i], type: types[i], day: key, time: time, start: start,
                                    seconds: Double(1500 + i * 420), metres: types[i] == "breathwork" || types[i].contains("strength") ? nil : Double(3000 + i * 2500) + (walky ? 500 : 0),
                                    avgHr: types[i] == "breathwork" ? nil : Double(112 + i * 4)))
        }
        return MonthWorkouts.ofMonth(out, day: day)
    }
    #endif
}

struct MonthWorkoutsCard: View {
    let day: String
    /* Opens a workout as a tap on the curve does: (the workout, all of that day's workouts, that day "yyyy-MM-dd"). */
    let open: (BodyDay.Workout, [BodyDay.Workout], String) -> Void
    @ObservedObject private var reader = MonthWorkoutsReader.shared
    @State private var showAll = false

    private static let rowsShown = 6

    private func tapped(_ w: MonthWorkout, from all: [MonthWorkout]) {
        let ofDay = MonthWorkouts.ofDay(all, day: w.day).map(MonthWorkouts.asBodyWorkout)
        open(MonthWorkouts.asBodyWorkout(w), ofDay, w.day)
    }

    var body: some View {
        let all = reader.shown(day: day)
        VStack(alignment: .leading, spacing: 1) {
            Text("WORKOUTS · \(MonthWorkouts.monthName(day))")
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body).lineLimit(1)
            if all.isEmpty {
                Text("No workouts from Garmin yet this month. They fill in once Garmin is connected and the watch has synced.")
                    .font(.caption).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("body-month-empty")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(all.count)).font(.title2.weight(.bold))
                    Text("this month").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.text)
                Text(MonthWorkouts.totalsLine(all)).font(.caption).foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("body-month-totals")
                VStack(spacing: 0) {
                    ForEach(Array(all.prefix(Self.rowsShown))) { w in
                        MonthWorkoutRow(w: w) { tapped(w, from: all) }
                        if w.id != all.prefix(Self.rowsShown).last?.id { Divider() }
                    }
                }
                .padding(.top, 6)
                if all.count > Self.rowsShown {
                    Button { showAll = true } label: {
                        Text("All \(all.count) workouts").font(.footnote.weight(.semibold)).foregroundStyle(Theme.body)
                    }
                    .buttonStyle(.plain).padding(.top, 6)
                    .accessibilityIdentifier("body-month-all")
                }
                Text("Tap a workout to open it.").font(.caption2).foregroundStyle(Theme.secondary).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-month-card")
        .sheet(isPresented: $showAll) {
            MonthWorkoutsSheet(all: all, month: MonthWorkouts.monthName(day)) { w in
                showAll = false
                // The sheet closes first, then the workout opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tapped(w, from: all) }
            }
        }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["AMSWS_BODY_SHEET"] == "month" { showAll = true } }
        #endif
    }
}

private struct MonthWorkoutRow: View {
    let w: MonthWorkout
    let action: () -> Void

    var body: some View {
        let sport = MonthWorkouts.colourSport(w.type)
        let tint: Color = sport.map { Theme.sport($0) } ?? Theme.secondary
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(BodyPage.shortName(type: w.type, name: w.name).uppercased())
                        .font(.caption2.weight(.bold)).foregroundStyle(sport == nil ? Theme.text : Color.black.opacity(0.85))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(sport == nil ? Theme.border : tint))
                    Text(MonthWorkouts.whenText(w)).font(.caption).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
                Text(w.name.isEmpty ? BodyPage.shortName(type: w.type, name: w.name) : w.name)
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 8) {
                    if w.seconds > 0 { Text(formatDuration((w.seconds / 60).rounded() * 60)) }
                    if let m = w.metres { Text(MonthWorkouts.kilometres(m)) }
                    if let hr = w.avgHr { Text("\(Int(hr.rounded())) bpm") }
                }
                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(BodyPage.shortName(type: w.type, name: w.name)), \(MonthWorkouts.whenText(w)), \(w.name). Opens it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("body-month-row-" + w.id)
    }
}

private struct MonthWorkoutsSheet: View {
    let all: [MonthWorkout]
    let month: String
    let pick: (MonthWorkout) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(all) { w in
                        MonthWorkoutRow(w: w) { pick(w) }
                        Divider()
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
            }
            .background(Theme.bodyGround.ignoresSafeArea())
            .navigationTitle("Workouts · \(month.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("body-month-done")
                }
            }
        }
        .presentationDetents([.large])
        .tint(Theme.body)
        .accessibilityIdentifier("body-month-sheet")
    }
}
