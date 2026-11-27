import SwiftUI
import MapKit
import WorkoutCore

/*
 * 2.19 Routes: the Progress card (a small quiet map of this month's outdoor
 * routes) and the Routes page (every route of a month on one map you can move
 * and zoom, with sport chips, a month switcher and a plate for a tapped
 * route). Shown only; the routes come from Garmin and never reach the plan.
 */

private enum RoutesLook {
    static func colour(_ sport: String) -> Color {
        // A hike wears the slate the app gives hikes and walks everywhere (Extras: colorId "rest"); orange is strength's.
        Theme.sport(sport == "hike" ? "rest" : sport)
    }
    static func ink(_ sport: String) -> Color { Theme.sportInk(sport == "hike" ? "rest" : sport) }
    static let words = ["run": "Run", "bike": "Bike", "swim": "Swim", "hike": "Hike"]

    static func region(_ routes: [RouteItem]) -> MKCoordinateRegion {
        // 2.19.3: frame where most routes are; a far-away one is still drawn (Routes31.focus).
        guard let r = Routes31.region(of: Routes31.focus(routes.map(\.track))) else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47, longitude: 8), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: r.centreLat, longitude: r.centreLon),
                                  span: MKCoordinateSpan(latitudeDelta: max((r.maxLat - r.minLat) * 1.35, 0.01),
                                                         longitudeDelta: max((r.maxLon - r.minLon) * 1.35, 0.01)))
    }

    /* 2.19.3: what an empty card or page says — never "no sessions" while reading or after a failed read. */
    @MainActor static func emptyLine(_ reader: RoutesReader, _ month: String) -> String {
        if let p = reader.progress { return p }
        if reader.isLoading(month) { return "Reading your routes\u{2026}" }
        if reader.failed.contains(month) { return "Garmin did not answer just now. Tap to try again." }
        return "No outdoor sessions this month yet."
    }

    /* "12 routes · 5 runs · 6 rides · 1 hike" */
    static func countLine(_ routes: [RouteItem]) -> String {
        func n(_ sport: String) -> Int { routes.filter { $0.sport == sport }.count }
        var parts = ["\(routes.count) route\(routes.count == 1 ? "" : "s")"]
        for (sport, one, many) in [("run", "run", "runs"), ("bike", "ride", "rides"), ("swim", "swim", "swims"), ("hike", "hike", "hikes")] where n(sport) > 0 {
            parts.append("\(n(sport)) \(n(sport) == 1 ? one : many)")
        }
        return parts.joined(separator: " · ")
    }
}

/* The lines of the routes, each in its sport's colour, with a white edge so a green run stays clear on a green map. */
private struct RouteLines: MapContent {
    let routes: [RouteItem]
    var selected: Int? = nil
    let width: CGFloat

    var body: some MapContent {
        ForEach(routes) { r in
            MapPolyline(coordinates: r.coordinates).stroke(Color.white, lineWidth: width + (r.id == selected ? 4 : 2.5))
        }
        ForEach(routes) { r in
            MapPolyline(coordinates: r.coordinates).stroke(RoutesLook.colour(r.sport), lineWidth: width)
        }
    }
}

// MARK: - Progress card

struct RoutesCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var reader = RoutesReader.shared
    /* AMSWS_ROUTES_PAGE=1 (DEBUG) opens the page at once, for a picture. */
    #if DEBUG
    @State private var open = ProcessInfo.processInfo.environment["AMSWS_ROUTES_PAGE"] != nil
    #else
    @State private var open = false
    #endif

    private var month: String { Routes31.monthKey(ofDay: store.today) }

    var body: some View {
        Group {
            // Without a key the card keeps its name and says how it fills, like the Body cards (never hidden).
            if GarminKey.isSaved { card } else { noKey }
        }
        .task { await reader.load(month: month) }
        // Closed through this binding, like the Pool card: the environment's dismiss did not close it on the Mac (2.19.2).
        .fullScreenCover(isPresented: $open) { RoutesPage(month: month, today: store.today, close: { open = false }) }
    }

    private var noKey: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ROUTES").font(.caption.weight(.bold)).foregroundStyle(Theme.progress)
            Text("Routes come from Garmin. Add your Garmin key in Settings \u{203A} Garmin.")
                .font(.subheadline).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-routes-card")
    }

    private var card: some View {
        let routes = reader.routes(month)
        return Button { open = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ROUTES").font(.caption.weight(.bold)).foregroundStyle(Theme.progress)
                    Text(Routes31.monthTitle(month)).font(.caption).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
                if routes.isEmpty {
                    Text(RoutesLook.emptyLine(reader, month)).font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    Map(initialPosition: .region(RoutesLook.region(routes)), interactionModes: []) {
                        RouteLines(routes: routes, width: 2.5)
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .id(routes.map(\.id))
                    .frame(height: Device.isPhone ? 140 : 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .allowsHitTesting(false)
                    Text(RoutesLook.countLine(routes)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(reader.progress ?? "Tap to open the map").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-routes-card")
    }
}

// MARK: - the page

struct RoutesPage: View {
    @ObservedObject private var reader = RoutesReader.shared
    let today: String
    @State private var month: String
    @State private var hidden: Set<String> = []
    @State private var selected: Int?
    @State private var position: MapCameraPosition = .automatic

    let close: () -> Void

    init(month: String, today: String, close: @escaping () -> Void) {
        self.today = today
        self.close = close
        _month = State(initialValue: month)
    }

    private var currentMonth: String { Routes31.monthKey(ofDay: today) }
    private var all: [RouteItem] { reader.routes(month) }
    private var shown: [RouteItem] { all.filter { !hidden.contains($0.sport) } }
    private var picked: RouteItem? { shown.first { $0.id == selected } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !GarminKey.isSaved {
                note("Routes come from Garmin. Add your Garmin key in Settings › Garmin.")
            } else if all.isEmpty {
                note(RoutesLook.emptyLine(reader, month))
            } else {
                mapView
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .task(id: month) {
            selected = nil
            await reader.load(month: month)
            fit()
        }
        .onChange(of: shown.map(\.id)) { _, _ in fit() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Routes").font(.headline).foregroundStyle(Theme.progress)
                Spacer(minLength: 0)
                Button("Done") { close() }
                    .settingsButton(tint: Theme.progress, filled: true)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("routes-done")
            }
            HStack(spacing: 14) {
                Button { month = Routes31.shift(month, by: -1) } label: { Text("‹").font(.title2.weight(.semibold)).frame(minWidth: 32, minHeight: 32) }
                    .accessibilityLabel("Previous month").accessibilityIdentifier("routes-month-prev")
                Text(Routes31.monthTitle(month)).font(.headline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("routes-month")
                Button { month = Routes31.shift(month, by: 1) } label: { Text("›").font(.title2.weight(.semibold)).frame(minWidth: 32, minHeight: 32) }
                    .disabled(month >= currentMonth)
                    .accessibilityLabel("Next month").accessibilityIdentifier("routes-month-next")
                Spacer(minLength: 0)
            }
            .tint(Theme.progress)
            HStack(spacing: 8) {
                ForEach(Routes31.sports, id: \.self) { chip($0) }
                Spacer(minLength: 0)
            }
            if let p = reader.progress {
                Text(p).font(.caption).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func chip(_ sport: String) -> some View {
        let on = !hidden.contains(sport)
        let colour = RoutesLook.colour(sport)
        return Button {
            if on { hidden.insert(sport) } else { hidden.remove(sport) }
        } label: {
            Text(RoutesLook.words[sport] ?? sport).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color(hex: 0x10201f) : RoutesLook.ink(sport))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(on ? colour : Color.clear))
                .overlay(Capsule().strokeBorder(colour, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "shown" : "hidden")
        .accessibilityIdentifier("routes-filter-\(sport)")
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .overlay(alignment: .bottom) { Spacer() }
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position) {
                RouteLines(routes: shown, selected: selected, width: 3.5)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .onTapGesture { point in selected = nearest(to: point, proxy: proxy) }
        }
        .overlay(alignment: .bottom) {
            if let r = picked { plate(r) }
        }
    }

    private func plate(_ r: RouteItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(r.name.isEmpty ? (RoutesLook.words[r.sport] ?? "") : r.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(Dates.short(r.day)).font(.caption).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let m = r.metres { Text(String(format: "%.1f km", m / 1000)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text) }
                Text(formatDuration(r.seconds)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(RoutesLook.colour(r.sport)).frame(width: 4).padding(.vertical, 8) }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("routes-plate")
    }

    private func fit() {
        guard !shown.isEmpty else { return }
        position = .region(RoutesLook.region(shown))
    }

    /* The route whose line passes within a fingertip of the tap, if any. */
    private func nearest(to tap: CGPoint, proxy: MapProxy) -> Int? {
        var best: (id: Int, d: CGFloat)?
        for r in shown {
            let pts = r.coordinates.compactMap { proxy.convert($0, to: .local) }
            for i in 1..<max(pts.count, 1) {
                let d = Self.distance(tap, pts[i - 1], pts[i])
                if d < 24, d < (best?.d ?? .infinity) { best = (r.id, d) }
            }
        }
        return best?.id
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
