import SwiftUI
import WorkoutCore

/* Solid is recorded, hollow is still to do, hatched is marked missed — the web app's alphabet. */
enum SessionState { case done, todo, missed }

extension Workout {
    var state: SessionState { missed ? .missed : (loggedInSheet ? .done : .todo) }
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
    let workout: Workout
    let mapping: Mapping
    var showDay = false

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
                }
            }
            Spacer(minLength: 0)
            if workout.state == .done { DoneTick() }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(border, style: StrokeStyle(lineWidth: workout.state == .todo ? 1 : 2))
        )
    }

    private var border: Color {
        switch workout.state {
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
