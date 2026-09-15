import SwiftUI
import WorkoutCore

/* Solid is recorded, hollow is still to do, hatched is marked missed — the web app's alphabet. */
enum SessionState { case done, todo, missed }

extension Workout {
    var state: SessionState { missed ? .missed : (logged ? .done : .todo) }
    var waitingLabel: String? {
        if pending != nil { return missed ? "Missed · waiting to sync" : "Waiting to sync" }
        if pendingMove != nil { return "Moved · waiting to sync" }
        return nil
    }
}

struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return p
    }
}

/* One session as a bar or a block: its colour, filled according to what happened. */
struct StateFill: View {
    let sport: String
    let state: SessionState
    var corner: CGFloat = 3

    var body: some View {
        let colour = Theme.sport(sport)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        switch state {
        case .done:
            shape.fill(colour)
        case .todo:
            shape.fill(colour.opacity(0.26)).overlay(shape.strokeBorder(Theme.sportInk(sport), lineWidth: 1.5))
        case .missed:
            shape.fill(Color.clear)
                .overlay(Hatch().stroke(colour, lineWidth: 1.4).clipShape(shape))
                .opacity(0.8)
        }
    }
}

struct DoneTick: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.today)
            Glyph(name: "icon-check", size: 15).foregroundStyle(Color.white)
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel("Done")
    }
}

struct SessionCard: View {
    @EnvironmentObject var store: Store
    let workout: Workout
    let mapping: Mapping
    var showDay = false

    private var shown: SessionState { workout.state }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SportBadge(discipline: workout.discipline)
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.discipline.label.uppercased())
                    .font(.caption.weight(.bold)).tracking(0.6)
                    .foregroundStyle(Theme.sportInk(workout.discipline.id))
                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if showDay { Pill(text: Dates.short(workout.dayKey)) }
                    if let seconds = Plan.plannedSeconds(workout, mapping), seconds > 0 {
                        Pill(text: formatDuration(seconds))
                    }
                    if !workout.planned.intensity.isEmpty { Pill(text: workout.planned.intensity) }
                    if workout.missed { Pill(text: "Missed", tint: Theme.danger) }
                    if let label = workout.waitingLabel { Pill(text: label, tint: Theme.today) }
                }
            }
            Spacer(minLength: 0)
            if shown == .done { DoneTick() }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(border, style: StrokeStyle(lineWidth: shown == .todo ? 1 : 2))
        )
    }

    private var border: Color {
        switch shown {
        case .done: return Theme.today
        case .missed: return Theme.danger.opacity(0.7)
        case .todo: return Theme.border
        }
    }
}

struct SectionHeading: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold)).tracking(0.8)
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}


/* Outside the plan: the activity's own colour, dotted down the middle — the web app's v1.71.1 drawing. */
struct DottedFill: View {
    let colorId: String
    var body: some View {
        let colour = Theme.sport(colorId)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(colour.opacity(0.22))
            .overlay(
                GeometryReader { geo in
                    let n = max(1, Int(geo.size.height / 6))
                    VStack(spacing: 3) {
                        ForEach(0..<n, id: \.self) { _ in Circle().fill(colour).frame(width: 3, height: 3) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                .foregroundStyle(colour))
    }
}

struct ExtraCard: View {
    let extra: ExtraSummary
    var body: some View {
        let activity = Extras.activity(extra.activity)
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.sport(activity.colorId).opacity(0.22))
                Glyph(name: activity.icon, size: 22).foregroundStyle(Theme.sportInk(activity.colorId))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text("EXTRA · " + extra.label.uppercased())
                    .font(.caption.weight(.bold)).tracking(0.6)
                    .foregroundStyle(Theme.sportInk(activity.colorId))
                Text(extra.what.isEmpty ? extra.label : extra.what)
                    .font(.headline).foregroundStyle(Theme.text).lineLimit(2)
                HStack(spacing: 6) {
                    if let m = extra.minutes { Pill(text: formatDuration(m * 60)) }
                    Pill(text: extra.isTraining ? "Counts as training" : "Not training load")
                    if extra.pending { Pill(text: "Waiting to sync", tint: Theme.today) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundStyle(Theme.sport(activity.colorId)))
    }
}
