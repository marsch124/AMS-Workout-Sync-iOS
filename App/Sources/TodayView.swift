import SwiftUI
import WorkoutCore

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var addingExtra = false
    @State private var openExtra: ExtraSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let view = store.view {
                    content(view)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                } else {
                    EmptyWorkbook()
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .refreshable { store.refresh() }
            .navigationDestination(for: String.self) { key in SessionView(key: key) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $addingExtra) { ExtraFormView(day: store.today).environmentObject(store) }
            .sheet(item: $openExtra) { x in ExtraDetailView(extra: x) }
            #if DEBUG
            .onAppear { if ProcessInfo.processInfo.environment["AMSWS_EXTRAFORM"] != nil { addingExtra = true } }
            #endif
        }
    }

    @ViewBuilder
    private func content(_ view: PlanView) -> some View {
        let today = store.today
        let sessions = view.forDay(today)
        let behind = view.outstanding(before: today).filter { $0.dayKey >= PlanView.addDays(today, -7) }
        let tomorrow = view.forDay(PlanView.addDays(today, 1))

        VStack(alignment: .leading, spacing: 14) {
            header(view, today)
            if let waited = store.waitedTooLong { WaitingWarning(text: waited) }
            WeekCard(view: view, today: today)

            if sessions.isEmpty {
                RestCard(text: "Nothing planned today")
            } else if sessions.allSatisfy({ $0.discipline.id == "rest" }) {
                RestCard(text: sessions[0].title)
            } else {
                ForEach(sessions) { w in
                    NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping) }
                        .accessibilityIdentifier("today-session-\(w.dayKey)-\(w.discipline.id)")
                        .buttonStyle(.plain)
                }
            }

            let todaysExtras = view.extras(on: today)
            if !todaysExtras.isEmpty {
                SectionHeading(text: "Extra, outside the plan")
                ForEach(todaysExtras) { x in
                    Button { openExtra = x } label: { ExtraCard(extra: x) }.buttonStyle(.plain)
                }
            }
            if store.canLog {
                Button { addingExtra = true } label: {
                    HStack(spacing: 8) {
                        Glyph(name: "icon-plus", size: 18)
                        Text("Extra activity")
                    }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered).tint(Theme.today)
            }

            if !behind.isEmpty {
                SectionHeading(text: "Behind you, not recorded")
                ForEach(behind) { w in
                    NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping, showDay: true) }
                        .accessibilityIdentifier("today-session-\(w.dayKey)-\(w.discipline.id)")
                        .buttonStyle(.plain)
                }
            }

            // Only tomorrow, as he asked: what to think about tonight, not the
            // week — and on its own pale blue ground, so the eye knows at once
            // that everything below the line is no longer today.
            if !tomorrow.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(text: "Tomorrow")
                    if tomorrow.allSatisfy({ $0.discipline.id == "rest" }) {
                        RestCard(text: tomorrow[0].title)
                    } else {
                        ForEach(tomorrow.filter { $0.discipline.id != "rest" }) { w in
                            NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping) }
                            .accessibilityIdentifier("today-session-\(w.dayKey)-\(w.discipline.id)")
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tomorrow))
                .padding(.horizontal, -12)
            }
        }
    }

    /* No date here: it is always today, and he would rather have the room (v1.0 (18)). */
    private func header(_ view: PlanView, _ today: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            let phase = view.phase(on: today)
            Text(phase.isEmpty ? "Today" : phase).font(.title3.weight(.bold)).foregroundStyle(Theme.today)
            Spacer()
            if store.canLog { PlanChip(name: store.fileName, syncing: store.syncing, waiting: store.queue.count) } else { ReadOnlyChip() }
        }
        .padding(.top, 12)
    }
}

/*
 * Logging that has waited a full day to reach Dropbox. Silent below that —
 * an ordinary send takes seconds, and a warning that appears on an ordinary
 * day is one you learn to ignore (web app v1.55.0).
 */
struct WaitingWarning: View {
    @EnvironmentObject var store: Store
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logging has not reached Dropbox").font(.headline).foregroundStyle(Theme.text)
            Text(text).font(.subheadline).foregroundStyle(Theme.secondary)
            Button(store.syncing ? "Sending…" : "Send it now") { store.syncNow() }
                .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).controlSize(.small).tint(Theme.danger)
                .disabled(store.syncing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.danger, lineWidth: 2))
    }
}

/* Stage 1 says what it is, once, small: this app looks and does not touch. */
struct ReadOnlyChip: View {
    var body: some View {
        Text("Read only")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().strokeBorder(Theme.border))
    }
}

/*
 * Says something only when there is something to say: that logging is on its
 * way, or that the app is pointed at a test copy rather than the plan. On the
 * real plan it shows nothing — "Writes to plan" sat there permanently and
 * read as a stuck message.
 */
struct PlanChip: View {
    let name: String
    let syncing: Bool
    let waiting: Int
    var body: some View {
        let isTest = name.lowercased().contains("test")
        if syncing || waiting > 0 || isTest {
            Text(syncing ? "Sending…" : (waiting > 0 ? "\(waiting) waiting" : "TEST COPY"))
                .font(.caption.weight(.bold))
                .foregroundStyle(isTest && !syncing && waiting == 0 ? Color.white : Theme.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(isTest && !syncing && waiting == 0 ? Color.orange : Color.clear))
                .overlay(Capsule().strokeBorder(isTest && !syncing && waiting == 0 ? Color.clear : Theme.border))
        }
    }
}

struct RestCard: View {
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            SportBadge(discipline: Disciplines.rest)
            Text(text).font(.headline).foregroundStyle(Theme.secondary).lineLimit(2)
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

/* The week drawn rather than described: a column a day, a bar a session. */
struct WeekCard: View {
    @EnvironmentObject var store: Store
    let view: PlanView
    let today: String
    /* Tap the card and the week explains its own drawing — a shape carries no label. */
    @State private var keyOpen = false

    var body: some View {
        let days = view.week(of: today, today: today)
        // Extras count towards the day total, or a two-hour hike would draw
        // a bar taller than the column it sits in.
        let tallest = max(days.map { $0.plannedSeconds + $0.extraSeconds }.max() ?? 0, 1)
        let planned = days.reduce(0) { $0 + $1.plannedSeconds }
        // The time actually recorded, as Progress counts it — the planned length
        // only where a session was marked done without a time. It used to add up
        // the planned lengths, so a 47-minute swim counted as its planned 45 and a
        // fully done week read "6h 32m of 6h 32m" whatever the watch said.
        let done = days.flatMap(\.training).filter { $0.state == .done }
            .reduce(0.0) { $0 + (Stats.actualSeconds($1, view.mapping) ?? Plan.plannedSeconds($1, view.mapping) ?? 0) }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.headline).foregroundStyle(Theme.text)
                Button(keyOpen ? "Hide key" : "Key") { withAnimation(.easeInOut(duration: 0.15)) { keyOpen.toggle() } }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini).tint(Theme.today)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(done > 0 ? "\(formatDuration(done)) of \(formatDuration(planned))" : "\(formatDuration(planned)) planned")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if planned > 0 {
                        WeekProgress(done: done, planned: planned,
                                     dueByToday: days.filter { $0.dayKey <= today }.reduce(0) { $0 + $1.plannedSeconds })
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            VStack(spacing: 3) {
                                Spacer(minLength: 0)
                                if day.isRest && day.extras.isEmpty {
                                    RoundedRectangle(cornerRadius: 2).fill(Theme.sport("rest"))
                                        .frame(width: geo.size.width * 0.6, height: 3)
                                } else {
                                    ForEach(day.training) { w in
                                        let seconds = Plan.plannedSeconds(w, view.mapping) ?? 0
                                        StateFill(sport: w.discipline.id, state: w.state)
                                            .frame(height: max(9, geo.size.height * seconds / tallest - 3))
                                    }
                                    ForEach(day.extras) { x in
                                        DottedFill(colorId: Extras.activity(x.activity).colorId)
                                            .frame(height: max(9, geo.size.height * x.seconds / tallest - 3))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 96)
                        Text(String(Dates.weekday.string(from: day.date).prefix(1)))
                            .font(.caption.weight(day.isToday ? .heavy : .semibold))
                            .foregroundStyle(day.isToday ? Theme.today : Theme.secondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(day.isToday ? Theme.today.opacity(0.18) : .clear))
                    }
                }
            }
            if keyOpen { WeekKey(days: days) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { keyOpen.toggle() } }
    }
}

/*
 * The key: what the shapes mean, then the colours. The five sports are always
 * listed, in training order, so the key is a key rather than a description of
 * this particular week; anything else the week holds is added after.
 */
struct WeekKey: View {
    let days: [PlanDay]

    var body: some View {
        let sports = Disciplines.five.map { ($0.id, $0.label) } + others + [("rest", "Rest / not a plan sport")]
        VStack(alignment: .leading, spacing: 10) {
            if !days.isEmpty { Divider() }
            HStack(spacing: 14) {
                keyItem(StateFill(sport: "run", state: .done), "Recorded")
                keyItem(StateFill(sport: "run", state: .todo), "Still to do")
                keyItem(StateFill(sport: "run", state: .missed), "Missed")
            }
            HStack(spacing: 14) {
                keyItem(DottedFill(colorId: "walk"), "Extra, outside the plan")
                keyItem(RoundedRectangle(cornerRadius: 2).fill(Theme.sport("rest")).frame(height: 3).frame(maxHeight: .infinity), "Rest day")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(sports, id: \.0) { id, label in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.sport(id)).frame(width: 10, height: 10)
                        Text(label).font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private var others: [(String, String)] {
        var seen: [(String, String)] = []
        for w in days.flatMap(\.training) where Disciplines.order(w.discipline.id) == Disciplines.five.count {
            if !seen.contains(where: { $0.0 == w.discipline.id }) { seen.append((w.discipline.id, w.discipline.label)) }
        }
        return seen
    }

    private func keyItem<Shape: View>(_ shape: Shape, _ label: String) -> some View {
        HStack(spacing: 6) {
            shape.frame(width: 14, height: 18)
            Text(label).font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

struct EmptyWorkbook: View {
    @EnvironmentObject var store: Store
    @State private var picking = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 80)
            Glyph(name: "icon-plan", size: 64).foregroundStyle(Theme.today)
            Text("Your training plan").font(.title2.weight(.bold)).foregroundStyle(Theme.text)
            if case .failed(let message) = store.phase {
                Text(message).font(.callout).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
            } else if store.phase == .loading {
                ProgressView()
            }
            Button {
                picking = true
            } label: {
                Text("Choose the workbook")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.today)
            Text("In Files, open Dropbox and pick your plan. This app only reads it.")
                .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .workbookPicker(isPresented: $picking)
    }
}


/*
 * The week as one hairline: how much of the planned time is recorded, and a
 * faint notch where the week should stand by the end of today. No words, no
 * percentage — it lives in the space the figures already leave.
 */
struct WeekProgress: View {
    let done: Double
    let planned: Double
    let dueByToday: Double

    var body: some View {
        let share = planned > 0 ? min(max(done / planned, 0), 1) : 0
        let pace = planned > 0 ? min(max(dueByToday / planned, 0), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                Capsule().fill(Theme.today).frame(width: max(geo.size.width * share, share > 0 ? 3 : 0))
                if pace > 0.02, pace < 0.98 {
                    // Where tonight's session leaves the week, if nothing slips.
                    Capsule().fill(Theme.secondary.opacity(0.7))
                        .frame(width: 1.5, height: geo.size.height + 4)
                        .offset(x: geo.size.width * pace - 0.75)
                }
            }
        }
        .frame(width: 96, height: 4)
    }
}
