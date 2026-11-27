import Foundation
import SwiftUI
import MapKit
import WorkoutCore

/*
 * 2.19 Routes: the outdoor sessions of one month, each with its track, read
 * from Garmin. A track comes first from the small file the session page
 * already keeps (garmin-activities/<id>.json, same format); only what is not
 * there is downloaded, one after the other, at most 20 per visit. Shown only:
 * nothing here reaches the plan. No key, no routes.
 */
struct RouteItem: Identifiable, Equatable {
    let id: Int
    let name: String
    let day: String
    let sport: String
    let metres: Double?
    let seconds: Double
    let track: [GarminCoordinate]

    var coordinates: [CLLocationCoordinate2D] { track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } }
}

@MainActor
final class RoutesReader: ObservableObject {
    static let shared = RoutesReader()
    static let maxDownloads = 20

    @Published private(set) var byMonth: [String: [RouteItem]] = [:]
    @Published private(set) var progress: String?
    /* 2.19.3: months whose list read failed (the card then says so, never "no sessions"), and months being read. */
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var loading: Set<String> = []

    func isLoading(_ month: String) -> Bool { loading.contains(month) }
    private var loadedAt: [String: Date] = [:]

    func routes(_ month: String) -> [RouteItem] { GarminKey.isSaved ? (byMonth[month] ?? []) : [] }

    /*
     * 2.20.1: the reading runs in a task of its own. On the Mac the Progress page lays its cards out twice
     * when it opens (narrow first, then two columns), so the first card's `.task` was cancelled half-way:
     * the reading ended as "Garmin did not answer" (Fitter at the same pulse on his Mac, 27 Nov 2026, three
     * times; very likely also the empty Routes card on first open). A started reading now always finishes.
     */
    func load(month: String) async {
        await Task { await self.loadNow(month: month) }.value
    }

    private func loadNow(month: String) async {
        #if DEBUG
        if GarminKey.isFake { byMonth[month] = Self.invented(month: month); return }
        #endif
        guard GarminKey.isSaved, !loading.contains(month) else { return }
        if let t = loadedAt[month], Date().timeIntervalSince(t) < 300 { return }
        loading.insert(month)
        defer { loading.remove(month); progress = nil }
        let list: [GarminActivitySummary]
        do { list = try await GarminClient.shared.activities(from: Routes31.firstDay(month), to: Routes31.lastDay(month)) } catch {
            failed.insert(month)
            return
        }
        failed.remove(month)
        let outdoor = list.filter { Routes31.sport(ofGarmin: $0.typeKey) != nil }.sorted { $0.day < $1.day }

        var found: [RouteItem] = []
        var pending: [GarminActivitySummary] = []
        for a in outdoor {
            if let d = Self.cached(a.id), d.recording.track.count >= 2 { found.append(Self.item(a, d.recording.track)) } else { pending.append(a) }
        }
        byMonth[month] = found
        let todo = Array(pending.prefix(Self.maxDownloads))
        for (i, a) in todo.enumerated() {
            progress = "Reading \(i + 1) of \(todo.count) routes…"
            guard let rec = try? await GarminClient.shared.recording(activityId: a.id) else { continue }
            let made = GarminActivityDetail(activityId: a.id, typeKey: a.typeKey, avgHr: a.avgHr, maxHr: a.maxHr, recording: rec)
            if !rec.isEmpty || made.avgHr != nil, let data = try? JSONEncoder().encode(made) {
                try? data.write(to: GarminActivityReader.cacheURL(activityId: a.id), options: .atomic)
            }
            if rec.track.count >= 2 {
                found.append(Self.item(a, rec.track))
                byMonth[month] = found.sorted { $0.day < $1.day }
            }
        }
        // A month with downloads left over is read again on the next visit.
        if pending.count <= Self.maxDownloads { loadedAt[month] = Date() }
    }

    func forget() { byMonth = [:]; loadedAt = [:] }

    private static func cached(_ id: Int) -> GarminActivityDetail? {
        guard let data = try? Data(contentsOf: GarminActivityReader.cacheURL(activityId: id)) else { return nil }
        return try? JSONDecoder().decode(GarminActivityDetail.self, from: data)
    }

    private static func item(_ a: GarminActivitySummary, _ track: [GarminCoordinate]) -> RouteItem {
        RouteItem(id: a.id, name: a.name, day: a.day, sport: Routes31.sport(ofGarmin: a.typeKey) ?? "run",
                  metres: a.metres, seconds: a.seconds, track: Routes31.thin(track))
    }

    #if DEBUG
    /* Seven invented routes around an invented place; never a real one. */
    static func invented(month: String) -> [RouteItem] {
        let plan: [(String, String, Double, Double, Double, Double)] = [
            // sport, name, centre lat offset, lon offset, size, kilometres
            ("run", "Morning run", 0.000, 0.000, 1.0, 8.2), ("run", "Easy run", 0.004, -0.010, 0.8, 6.1),
            ("bike", "Ride out", 0.010, 0.020, 3.0, 54.0), ("bike", "Long ride", -0.015, 0.012, 4.0, 82.5),
            ("run", "Intervals", 0.002, 0.004, 0.6, 5.4), ("swim", "Open water", -0.006, -0.018, 0.5, 1.9),
            ("hike", "Hill walk", 0.018, -0.016, 1.6, 11.3)]
        return plan.enumerated().map { i, p in
            let track = (0...80).map { k -> GarminCoordinate in
                let a = Double(k) / 80 * 2 * .pi
                return GarminCoordinate(lat: 47.0 + p.2 + 0.010 * p.4 * sin(a) + 0.003 * p.4 * sin(3 * a + Double(i)),
                                        lon: 8.0 + p.3 + 0.015 * p.4 * cos(a))
            }
            return RouteItem(id: 9000 + i, name: p.1, day: month + "-" + String(format: "%02d", 2 + i * 3), sport: p.0,
                             metres: p.5 * 1000, seconds: p.5 * (p.0 == "bike" ? 120 : 330), track: track)
        }
    }
    #endif
}
