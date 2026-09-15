import SwiftUI
import WorkoutCore

struct TodayView: View {
    @EnvironmentObject var store: Store

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
        }
    }

    @ViewBuilder
    private func content(_ view: PlanView) -> some View {
        let today = store.today
        let sessions = view.forDay(today)
        let behind = view.outstanding(before: today).filter { $0.dayKey >= PlanView.addDays(today, -7) }
        let next = view.upcoming(from: today, limit: 3)

        VStack(alignment: .leading, spacing: 14) {
            header(view, today)
            WeekCard(view: view, today: today)

            if sessions.isEmpty {
                RestCard(text: "Nothing planned today")
            } else if sessions.allSatisfy({ $0.discipline.id == "rest" }) {
                RestCard(text: sessions[0].title)
            } else {
                ForEach(sessions) { w in
                    NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping) }
                        .buttonStyle(.plain)
                }
            }

            if !behind.isEmpty {
                SectionHeading(text: "Behind you, not recorded")
                ForEach(behind) { w in
                    NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping, showDay: true) }
                        .buttonStyle(.plain)
                }
            }

            if !next.isEmpty {
                SectionHeading(text: "Coming up")
                ForEach(next) { w in
                    NavigationLink(value: w.key) { SessionCard(workout: w, mapping: view.mapping, showDay: true) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func header(_ view: PlanView, _ today: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                let phase = view.phase(on: today)
                if !phase.isEmpty {
                    Text(phase).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.today)
                }
                Text(Dates.long(today))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer()
            if store.canLog { PlanChip(name: store.fileName, syncing: store.syncing, waiting: store.queue.count) } else { ReadOnlyChip() }
        }
        .padding(.top, 12)
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

/* Which workbook logging goes into — so the test copy can never be mistaken for the plan. */
struct PlanChip: View {
    let name: String
    let syncing: Bool
    let waiting: Int
    var body: some View {
        let isTest = name.lowercased().contains("test")
        Text(syncing ? "Sending…" : (waiting > 0 ? "\(waiting) waiting" : (isTest ? "TEST COPY" : "Writes to plan")))
            .font(.caption.weight(.bold))
            .foregroundStyle(isTest ? Color.white : Theme.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(isTest ? Color.orange : Color.clear))
            .overlay(Capsule().strokeBorder(isTest ? Color.clear : Theme.border))
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

    var body: some View {
        let days = view.week(of: today, today: today)
        let tallest = max(days.map(\.plannedSeconds).max() ?? 0, 1)
        let planned = days.reduce(0) { $0 + $1.plannedSeconds }
        let done = days.flatMap(\.training).filter { $0.state == .done }
            .reduce(0.0) { $0 + (Plan.plannedSeconds($1, view.mapping) ?? 0) }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Text(done > 0 ? "\(formatDuration(done)) of \(formatDuration(planned))" : "\(formatDuration(planned)) planned")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            VStack(spacing: 3) {
                                Spacer(minLength: 0)
                                if day.isRest {
                                    RoundedRectangle(cornerRadius: 2).fill(Theme.sport("rest"))
                                        .frame(width: geo.size.width * 0.6, height: 3)
                                } else {
                                    ForEach(day.training) { w in
                                        let seconds = Plan.plannedSeconds(w, view.mapping) ?? 0
                                        StateFill(sport: w.discipline.id, state: w.state)
                                            .frame(height: max(9, geo.size.height * seconds / tallest - 3))
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
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
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
