import SwiftUI
import UIKit
import WorkoutCore

/*
 * Two messages, the web app's wording kept. The brief is the whole session —
 * intensity, purpose, the warm-up and the interval set — which is what a
 * training partner wants. "What you did" is one sentence for the person at
 * home: back, and how long. Heart rate and effort are left out of both on
 * purpose; they are between him and the workbook.
 */
enum ShareText {
    static func session(_ w: Workout, _ mapping: Mapping) -> String {
        let planned = Plan.plannedSeconds(w, mapping).flatMap { $0 > 0 ? formatDuration($0) : nil } ?? ""
        var lines: [String] = []
        lines.append(Dates.long(w.dayKey) + " — " + w.discipline.label + (planned.isEmpty ? "" : ", " + planned))
        if !w.title.isEmpty { lines.append(w.title) }

        var detail: [String] = []
        if !w.planned.intensity.isEmpty { detail.append("Intensity: " + w.planned.intensity) }
        let purpose = w.planned.description
        if !purpose.isEmpty { detail.append("Purpose: " + purpose) }
        for s in w.sections where purpose.isEmpty || s.text != purpose { detail.append(s.label + ": " + s.text) }
        if !detail.isEmpty {
            lines.append("")
            lines.append(contentsOf: detail.map { "  • " + $0 })
        }

        switch w.state {
        case .done:
            lines.append("")
            lines.append(actualSeconds(w, mapping).map { "Done — " + formatDuration($0) } ?? "Done.")
        case .missed:
            lines.append("")
            lines.append("Marked missed.")
        case .todo:
            break
        }
        return lines.joined(separator: "\n")
    }

    static func done(_ w: Workout, _ mapping: Mapping, today: String) -> String {
        let figures = doneFigures(w, mapping).joined(separator: ", ")
        let sport = w.discipline.label.lowercased()
        var lines: [String] = []
        if w.dayKey == today {
            lines.append("Just finished today’s " + sport + (figures.isEmpty ? "" : " — " + figures) + ".")
        } else {
            lines.append(Dates.long(w.dayKey) + "’s " + sport + " is done" + (figures.isEmpty ? "" : " — " + figures) + ".")
        }
        if !w.title.isEmpty { lines.append(w.title) }
        return lines.joined(separator: "\n")
    }

    /* The waiting log first, then the sheet — as the web app reads it. */
    static func actualSeconds(_ w: Workout, _ mapping: Mapping) -> Double? {
        if let p = w.pending { return parseDuration(p.actualDuration) }
        if let n = w.results["actualDuration"]?.number { return durationFromCell(n, mapping.units.duration) }
        return nil
    }

    static func doneFigures(_ w: Workout, _ mapping: Mapping) -> [String] {
        var out: [String] = []
        if let s = actualSeconds(w, mapping), s > 0 { out.append(formatDuration(s)) }
        let distance: Double?
        if let p = w.pending {
            distance = p.actualDistance.flatMap { Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
        } else {
            distance = w.results["actualDistance"]?.number
        }
        if let d = distance, d > 0 { out.append(jsNumberString(d) + " " + mapping.units.distance) }
        return out
    }

    @MainActor static func photos(_ w: Workout) -> [UIImage] {
        let store = PhotoStore.shared
        return store.photos(for: PhotoOwner(w)).compactMap { store.image($0.id) }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/* The system share sheet: Messages, Mail, whatever is on the phone. */
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
