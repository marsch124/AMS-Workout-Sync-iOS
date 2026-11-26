import SwiftUI
import WorkoutCore

/*
 * The two questions, each answered with one tap.
 *
 *   "How do you feel?"   — Today, once a morning, five faces with a word each.
 *   "How hard was it?"   — after Done, the numbers 1 to 10.
 *
 * Neither leads to advice. The first is kept on the phone; the second goes
 * into the plan's own Effort column.
 */

/*
 * One of the five faces. Apple's symbol set has a single face, the smiling
 * one, so all five are drawn here in its manner — a thin round line, two oval
 * eyes — and differ only in the mouth (his pick of 24 November 2026: "Faces
 * but Apple SF icons", then look 1 of the three ways round the missing
 * faces). Drawn on a 24-point grid and scaled.
 */
struct FaceMark: View {
    let feel: Feel
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            FaceLines(feel: feel)
                .stroke(style: StrokeStyle(lineWidth: size * 1.55 / 24, lineCap: .round, lineJoin: .round))
            FaceEyes(feel: feel).fill()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct FaceLines: Shape {
    let feel: Feel
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + 2.8 * s, y: rect.minY + 2.8 * s, width: 18.4 * s, height: 18.4 * s))
        switch feel {
        case .bad:
            path.move(to: p(7.9, 16.6))
            path.addCurve(to: p(12, 14), control1: p(8.8, 14.9), control2: p(10.2, 14))
            path.addCurve(to: p(16.1, 16.6), control1: p(13.8, 14), control2: p(15.2, 14.9))
        case .tired:
            // Eyes closed: two short lines where the others have ovals.
            path.move(to: p(7.6, 10)); path.addLine(to: p(10.2, 10))
            path.move(to: p(13.8, 10)); path.addLine(to: p(16.4, 10))
            path.move(to: p(8.7, 16))
            path.addCurve(to: p(12, 14.8), control1: p(9.7, 15.2), control2: p(10.8, 14.8))
            path.addCurve(to: p(15.3, 16), control1: p(13.2, 14.8), control2: p(14.3, 15.2))
        case .ok:
            path.move(to: p(8.4, 15.4)); path.addLine(to: p(15.6, 15.4))
        case .good:
            path.move(to: p(7.9, 14.2))
            path.addCurve(to: p(12, 16.8), control1: p(8.8, 15.9), control2: p(10.2, 16.8))
            path.addCurve(to: p(16.1, 14.2), control1: p(13.8, 16.8), control2: p(15.2, 15.9))
        case .great:
            path.move(to: p(7.2, 13.3)); path.addLine(to: p(16.8, 13.3))
            path.addCurve(to: p(12, 17.6), control1: p(16.4, 16), control2: p(14.6, 17.6))
            path.addCurve(to: p(7.2, 13.3), control1: p(9.4, 17.6), control2: p(7.6, 16))
            path.closeSubpath()
        }
        return path
    }
}

private struct FaceEyes: Shape {
    let feel: Feel
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard feel != .tired else { return path }
        let s = rect.width / 24
        let y: CGFloat = feel == .great ? 9.3 : 9.7
        for x in [CGFloat(8.9), 15.1] {
            path.addEllipse(in: CGRect(x: rect.minX + (x - 0.95) * s, y: rect.minY + (y - 1.45) * s,
                                       width: 1.9 * s, height: 2.9 * s))
        }
        return path
    }
}

/*
 * The morning question. A tap on a face saves it at once; the card then stays
 * for "Anything to add?" — a few words that travel with the answer. Save keeps
 * them, Skip leaves any earlier comment as it was.
 */
struct FeelCard: View {
    /* Today's answer while he is changing it; nil the first time. */
    var current: Feel?
    /* The comment already given today, put in the field. */
    var note: String = ""
    let pick: (Feel) -> Void
    var saveNote: (String) -> Void = { _ in }
    var skip: () -> Void = {}

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How do you feel?")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .accessibilityIdentifier("feel-question")
            HStack(spacing: 6) {
                ForEach(Feel.allCases) { f in
                    Button { pick(f) } label: {
                        VStack(spacing: 2) {
                            FaceMark(feel: f).foregroundStyle(Theme.text)
                            Text(f.word).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 7).padding(.bottom, 5)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(current == f ? Theme.today.opacity(0.14) : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(current == f ? Theme.today : Theme.border, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feel-\(f.rawValue)")
                    .accessibilityLabel(f.word)
                }
            }
            if current != nil {
                Text("Anything to add?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    .padding(.top, 2)
                TextField("A few words, like slept badly or sore legs", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .focused($focused)
                    .onChange(of: text) { _, new in if new.count > 200 { text = String(new.prefix(200)) } }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .accessibilityIdentifier("feel-note-field")
                HStack(spacing: 10) {
                    Button { saveNote(text.trimmingCharacters(in: .whitespacesAndNewlines)) } label: {
                        Text("Save").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.today))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("feel-note-save")
                    Button { skip() } label: {
                        Text("Skip").font(.subheadline).foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("feel-note-skip")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .onAppear {
            text = note
            if current != nil { focused = true }
        }
        .onChange(of: current) { old, new in
            if old == nil, new != nil { focused = true }
        }
    }
}

extension Feel {
    /* As it reads on the morning line: "Feeling good", "Feeling OK". */
    var spoken: String { "Feeling " + (self == .ok ? "OK" : word.lowercased()) }
}

/* The numbers 1 to 10, one tap. The words under it name three of them so the scale needs no memory. */
struct EffortRow: View {
    var tint: Color = Theme.today
    var idPrefix = "effort"
    let pick: (Int) -> Void

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(1...10, id: \.self) { n in
                    Button { pick(n) } label: {
                        Text("\(n)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(tint)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint, lineWidth: 1.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(idPrefix)-\(n)")
                    .accessibilityLabel("\(n) out of 10")
                }
            }
            HStack {
                Text("1 very easy")
                Spacer()
                Text("7 hard")
                Spacer()
                Text("10 all out")
            }
            .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

/* "How hard was it?" on a session's or an extra's own page, until it is answered. */
struct HowHardCard: View {
    let pick: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How hard was it?")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                .accessibilityIdentifier("how-hard-question")
            EffortRow(pick: pick)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}
