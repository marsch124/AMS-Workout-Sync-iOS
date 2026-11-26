import SwiftUI
import WorkoutCore

/*
 * 2.9 lane "load": the Training load and Fitness cards and their reader. One cached file (garmin-load.json), at most one
 * read in 30 minutes, only with a key. The load is the Board's own sum of each workout's Garmin training load.
 */
extension GarminClient {
    /* Twelve weeks of workouts (pages of 99) and the fitness age. */
    func load(day: String) async throws -> GarminLoadFile {
        var file = GarminLoadFile()
        var all: [LoadWorkout] = []
        var start = 0
        while start < 500 {
            let page = try await tolerant("/activitylist-service/activities/search/activities",
                                          ["startDate": GarminMorning.addDays(day, -83), "endDate": day, "limit": "99", "start": String(start)])
            let got = BodyLoad.workouts(page)
            all += got
            if got.count < 99 { break }
            start += 99
        }
        file.workouts = all
        file.fitness = BodyLoad.fitnessAge(try await tolerant("/fitnessage-service/fitnessage/v2/" + day))
        file.day = day
        file.readAt = Date()
        return file
    }
}

@MainActor
final class BodyLoadReader: ObservableObject {
    static let shared = BodyLoadReader()

    @Published private(set) var file = GarminLoadFile()
    @Published private(set) var reading = false

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-load.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(GarminLoadFile.self, from: data) { file = f }
        #if DEBUG
        if GarminKey.isFake {
            let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] ?? GarminMorning.dayKey(Date())
            file = Self.invented(day: day)
        }
        #endif
    }

    var shown: Bool { GarminKey.isSaved && !file.workouts.isEmpty }
    func summary(day: String) -> BodyLoad.Summary { BodyLoad.summary(file.workouts, today: day) }

    func readIfDue(today: String) async {
        guard GarminKey.isSaved, !GarminKey.isFake, GarminMorning.mayRead(lastTried: file.lastTried, now: Date()) else { return }
        await read(today: today)
    }

    func read(today: String) async {
        guard GarminKey.isSaved, !GarminKey.isFake, !reading else { return }
        reading = true
        file.lastTried = Date()
        let day = ProcessInfo.processInfo.environment["AMSWS_TODAY"] != nil ? today : GarminMorning.dayKey(Date())
        if let fresh = try? await GarminClient.shared.load(day: day) {
            // An empty answer never replaces numbers already held.
            if !fresh.workouts.isEmpty { file.workouts = fresh.workouts; file.day = fresh.day; file.readAt = fresh.readAt }
            if let f = fresh.fitness { file.fitness = f }
        }
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: Self.fileURL, options: .atomic) }
        reading = false
    }

    #if DEBUG
    /* Invented, for pictures: no network and no key. */
    static func invented(day: String) -> GarminLoadFile {
        var f = GarminLoadFile()
        f.day = day
        for k in 0..<84 where k % 2 == 0 || k % 5 == 0 {
            let d = GarminMorning.addDays(day, -k)
            f.workouts.append(LoadWorkout(day: d, load: 40 + Double((k * 29) % 45), vo2max: k == 3 ? 51 : nil))
        }
        f.fitness = FitnessAgeNumbers(fitnessAge: 52.4, realAge: 58)
        return f
    }
    #endif
}

// MARK: Training load

struct TrainingLoadCard: View {
    let day: String
    @ObservedObject private var reader = BodyLoadReader.shared
    @State private var open = false

    var body: some View {
        let s = reader.summary(day: day)
        Button { open = true } label: { face(s) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(s))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("body-training-load")
            .sheet(isPresented: $open) { TrainingLoadSheet(summary: s) }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["AMSWS_BODY_SHEET"] == "load" { open = true }
                #endif
            }
    }

    private func label(_ s: BodyLoad.Summary) -> String {
        guard reader.shown else { return "Training load. No load yet. Opens the last 12 weeks." }
        return "Training load \(BodyPage.grouped(s.acute)) 7 days. \(BodyLoad.ratioLine(s)). \(s.word ?? ""). Opens the last 12 weeks."
    }

    private func face(_ s: BodyLoad.Summary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TRAINING LOAD").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body)
                .lineLimit(1).minimumScaleFactor(0.8)
            if reader.shown {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(BodyPage.grouped(s.acute)).font(.title2.weight(.bold))
                    Text("7 days").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(BodyLoad.ratioLine(s)).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
                if let r = s.ratio, let word = s.word {
                    let danger = BodyLoad.isDanger(r)
                    Text(danger ? "\(word) · well above your usual" : word)
                        .font(.caption.weight(.semibold)).foregroundStyle(danger ? Color.red : Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 2)
                    LoadScale(ratio: r).padding(.top, 4)
                }
            } else {
                Text("No load yet").font(.title3.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.top, 2)
                Text("Fills from Garmin once workouts have a load. Tap for 12 weeks.")
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
        .contentShape(Rectangle())
    }
}

/* A slim round bar on a scale 0 to 2 with the steady stretch (0.8 to 1.3) a little darker and a small marker. */
struct LoadScale: View {
    let ratio: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.body.opacity(0.16))
                Capsule().fill(Theme.body.opacity(0.38))
                    .frame(width: w * CGFloat(BodyLoad.steady.upperBound - BodyLoad.steady.lowerBound))
                    .offset(x: w * CGFloat(BodyLoad.steady.lowerBound))
                Circle().fill(Theme.body).overlay(Circle().stroke(Theme.bodyTile, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .offset(x: min(max(w * CGFloat(BodyLoad.scalePosition(ratio)) - 6, 0), w - 12))
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

struct TrainingLoadSheet: View {
    let summary: BodyLoad.Summary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WEEKLY LOAD · LAST 12 WEEKS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body)
                    let top = max(summary.weeks.max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(summary.weeks.enumerated()), id: \.offset) { i, v in
                            VStack(spacing: 3) {
                                Capsule().fill(Theme.body.opacity(i == summary.weeks.count - 1 ? 1 : 0.55))
                                    .frame(height: max(4, 90 * CGFloat(v / top)))
                                Text(i == summary.weeks.count - 1 ? "now" : String(11 - i)).font(.caption2).foregroundStyle(Theme.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 112, alignment: .bottom)
                        }
                    }
                    Text("Each bar is 7 days of load; the numbers count the weeks back from now.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    if let r = summary.ratio, let word = summary.word {
                        Text("\(word) · ratio " + String(format: "%.2f", r)).font(.headline)
                            .foregroundStyle(BodyLoad.isDanger(r) ? Color.red : Theme.text).padding(.top, 6)
                    }
                    ForEach(Array(BodyLoad.meaning(summary.ratio).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
            }
            .background(Theme.bodyGround.ignoresSafeArea())
            .navigationTitle("Training load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("body-training-load-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.body)
        .accessibilityIdentifier("body-training-load-sheet")
    }
}

// MARK: Fitness

struct FitnessCard: View {
    let day: String
    @ObservedObject private var reader = BodyLoadReader.shared

    var body: some View {
        let n = reader.file.fitness
        let vo2 = BodyLoad.latestVo2(reader.file.workouts)
        VStack(alignment: .leading, spacing: 1) {
            Text("FITNESS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body)
                .lineLimit(1).minimumScaleFactor(0.8)
            if GarminKey.isSaved, let n {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(Int(n.fitnessAge.rounded()))).font(.title2.weight(.bold))
                    Text("fitness age").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(BodyLoad.ageLine(n) ?? " ").font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
                if let vo2 {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(String(Int(vo2.rounded()))).font(.headline.weight(.bold))
                        Text("VO2 max").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.text).padding(.top, 4)
                } else {
                    Text("VO2 max: Garmin does not share it yet").font(.caption).foregroundStyle(Theme.secondary)
                        .lineLimit(2).padding(.top, 4)
                }
            } else {
                Text("No fitness age yet").font(.title3.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.top, 2)
                Text("Fills from Garmin when it has worked one out.").font(.caption).foregroundStyle(Theme.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(n.map { "Fitness age \(Int($0.fitnessAge.rounded())). \(BodyLoad.ageLine($0) ?? "")" } ?? "Fitness. No fitness age yet.")
        .accessibilityIdentifier("body-fitness")
    }
}
