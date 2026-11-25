#if DEBUG
import SwiftUI
import WorkoutCore

/*
 * Pictures, DEBUG only, all with invented data that never touches the shelf:
 *   AMSWS_LOG_EXTRAS=1   the rows of the log form for an invented brick of 100 minutes, all showing
 *   AMSWS_DONE_EXTRAS=1  a done session's block with all four notes invented (also set on a real session page, it fills that page's block)
 *   AMSWS_NIGGLES_CARD=1 the Progress card
 *   AMSWS_FUEL_NOTES=1   the fuel notes page
 */
struct LogExtrasDebug: View {
    @EnvironmentObject var store: Store
    private let env = ProcessInfo.processInfo.environment

    var body: some View {
        if env["AMSWS_LOG_EXTRAS"] != nil, let w = store.displayed.first(where: { $0.discipline.id != "rest" }) {
            NavigationStack { LogExtrasPicture(workout: w) }.environmentObject(store)
        }
        if env["AMSWS_DONE_EXTRAS"] != nil, env["AMSWS_SESSION"] == nil, let w = store.displayed.first(where: { $0.discipline.id != "rest" }), let m = store.mapping {
            NavigationStack {
                ScrollView { SessionNotesBlock(workout: w, mapping: m).padding(16) }
                    .background(Theme.bg.ignoresSafeArea())
            }
        }
        if env["AMSWS_NIGGLES_CARD"] != nil {
            ScrollView { NigglesCard(sample: Self.niggles).padding(16) }
                .background(Theme.bg.ignoresSafeArea())
                .environmentObject(store)
        }
        if env["AMSWS_FUEL_NOTES"] != nil {
            NavigationStack { FuelNotesPage(sample: Self.fuel) }.environmentObject(store)
        }
    }

    static let calf = NiggleNote(place: "Calf", side: "left", line: "tight after the hills")
    static let niggles = [
        NiggleEntry(id: "a", day: "2026-11-16", title: "Hill repeats", note: calf),
        NiggleEntry(id: "b", day: "2026-11-12", title: "Easy run", note: NiggleNote(place: "Back", line: "stiff on waking")),
        NiggleEntry(id: "c", day: "2026-11-09", title: "Long run", note: calf),
        NiggleEntry(id: "d", day: "2026-11-02", title: "Tempo run", note: NiggleNote(place: "Calf", side: "left", line: "")),
    ]
    static let fuel = [
        FuelEntry(id: "a", day: "2026-11-15", title: "Long ride", seconds: 9600, note: StomachNote(answer: .fine, line: "Rice cakes and a gel an hour")),
        FuelEntry(id: "b", day: "2026-11-08", title: "Long run", seconds: 6300, note: StomachNote(answer: .soso, line: "Mix too sweet")),
        FuelEntry(id: "c", day: "2026-11-01", title: "Brick", seconds: 6000, note: StomachNote(answer: .upset, line: "")),
        FuelEntry(id: "d", day: "2026-10-25", title: "Long ride", seconds: 10800, note: StomachNote(answer: .fine, line: "Bananas, mix")),
    ]
}

/* The log form's extra rows on their own, for an invented brick of 100 minutes (the real form needs a real session). */
private struct LogExtrasPicture: View {
    let workout: Workout
    @State private var draft = LogExtrasDraft(bike: "1:05", change: "1:20", run: "30", stomach: .fine, stomachLine: "A gel every 30 minutes",
                                              niggle: NiggleNote(place: "Calf", side: "left", line: "tight"), waterOn: true, wetsuit: true, temp: "17", waterLine: "Calm")
    @State private var length = "1:40"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("BRICK · INVENTED, 100 MINUTES").font(.caption.weight(.bold)).foregroundStyle(Theme.plan)
                LogExtrasSection(workout: workout, draft: $draft, seconds: 6000, duration: $length, includeNiggle: true, forced: LogExtrasDraft.Applies(brick: true, stomach: true, water: true))
            }.padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif
