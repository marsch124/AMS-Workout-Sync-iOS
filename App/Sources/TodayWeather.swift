import SwiftUI
import CoreLocation
import WorkoutCore

/*
 * Weather and daylight for today's outdoor session: one calm grey line under
 * its card ("11° · feels 7° · breezy 5 m/s · rain likely 14–16  ·  Light until
 * 16:12"). The forecast comes from Open-Meteo (free, no key — the service AMS
 * Packing uses too). Only the coordinates, rounded to one decimal, leave the
 * phone. Location is asked "when in use", reduced accuracy; with no
 * permission, no network or no outdoor session the line is simply absent.
 */

enum WeatherSwitch {
    static let key = "weather-and-daylight-on-today"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /* AMSWS_FAKE_WEATHER=1: invented weather and daylight, no network, no permission. */
    static var fake: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_FAKE_WEATHER"] != nil
        #else
        return false
        #endif
    }
}

struct WeatherPlace: Equatable { let latitude: Double; let longitude: Double }

struct WeatherSnapshot {
    let day: String
    let place: WeatherPlace
    var hours: [WeatherHour]
    let fetchedAt: Date
}

@MainActor
final class TodayWeatherModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = TodayWeatherModel()
    @Published private(set) var snapshot: WeatherSnapshot?

    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<WeatherPlace?, Never>?
    private var askedAuthorisation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /* Today's forecast, from the cache when it is under an hour old. Never throws, never shows an error. */
    func refresh(day: String) async {
        if WeatherSwitch.fake { snapshot = Self.invented(day: day); return }
        guard WeatherSwitch.isOn else { snapshot = nil; return }
        if let s = snapshot, s.day == day, Date().timeIntervalSince(s.fetchedAt) < 3600 { return }
        guard let place = await locate() else { return }
        let hours = (try? await Self.forecast(place)) ?? []
        snapshot = WeatherSnapshot(day: day, place: place, hours: hours, fetchedAt: Date())
    }

    // MARK: place

    private func locate() async -> WeatherPlace? {
        guard waiting == nil else { return nil }
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        default: break
        }
        return await withCheckedContinuation { c in
            waiting = c
            if manager.authorizationStatus == .notDetermined {
                askedAuthorisation = true
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.askedAuthorisation, self.waiting != nil else { return }
            switch manager.authorizationStatus {
            case .notDetermined: return
            case .denied, .restricted: self.finish(nil)
            default: manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        Task { @MainActor in
            // One decimal is all that is kept or sent (about 10 km).
            self.finish(c.map { WeatherPlace(latitude: ($0.latitude * 10).rounded() / 10, longitude: ($0.longitude * 10).rounded() / 10) })
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ place: WeatherPlace?) {
        askedAuthorisation = false
        let c = waiting
        waiting = nil
        c?.resume(returning: place)
    }

    // MARK: forecast

    private static func forecast(_ place: WeatherPlace) async throws -> [WeatherHour] {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(format: "%.1f", place.latitude)),
            .init(name: "longitude", value: String(format: "%.1f", place.longitude)),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m"),
            .init(name: "wind_speed_unit", value: "ms"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        var request = URLRequest(url: url.url!, timeoutInterval: 10)
        request.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let h = root["hourly"] as? [String: Any], let times = h["time"] as? [String] else { return [] }
        func column(_ k: String) -> [Double?] { (h[k] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue } }
        let t = column("temperature_2m"), f = column("apparent_temperature")
        let r = column("precipitation_probability"), w = column("wind_speed_10m")
        var out: [WeatherHour] = []
        for (i, stamp) in times.enumerated() {
            // "2026-11-25T14:00": the hour is the two digits after the T (the forecast's own, local to the place).
            guard let hour = Int(stamp.dropFirst(11).prefix(2)), i < t.count, let temp = t[i] else { continue }
            out.append(WeatherHour(hour: hour, tempC: temp, feelsC: (i < f.count ? f[i] : nil) ?? temp,
                                   windMs: (i < w.count ? w[i] : nil) ?? 0, rainPercent: (i < r.count ? r[i] : nil) ?? 0))
        }
        return out
    }

    /* The picture switch: Stockholm-ish, a cool breezy afternoon with rain coming. */
    private static func invented(day: String) -> WeatherSnapshot {
        let hours = (0..<24).map { h in
            WeatherHour(hour: h, tempC: 9 + Double(min(h, 24 - h)) / 6, feelsC: 5 + Double(min(h, 24 - h)) / 6,
                        windMs: 5.2, rainPercent: (15...16).contains(h) ? 55 : 10)
        }
        return WeatherSnapshot(day: day, place: WeatherPlace(latitude: 59.3, longitude: 18.1), hours: hours, fetchedAt: Date())
    }
}

/* The line under today's session card; nothing at all when there is nothing to say. */
struct TodayWeatherLine: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var model = TodayWeatherModel.shared
    @AppStorage(WeatherSwitch.key) private var on = true
    let workout: Workout
    let mapping: Mapping

    var body: some View {
        let outdoor = on && OutdoorSession.isOutdoor(disciplineId: workout.discipline.id,
                                                     text: workout.title + " " + workout.planned.description)
        let parts = outdoor ? lineParts() : (nil, nil)
        Group {
            if parts.0 != nil || parts.1 != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { texts(parts, dot: true) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 1) { texts(parts, dot: false) }
                }
                .font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2).padding(.top, -6)
                .accessibilityElement(children: .contain)
            } else {
                // Nothing to show: no room taken either (the page spaces its rows 14 apart).
                Color.clear.frame(height: 0).padding(.top, -14).accessibilityHidden(true)
            }
        }
        .task(id: outdoor) { if outdoor { await model.refresh(day: store.today) } }
    }

    @ViewBuilder
    private func texts(_ parts: (String?, String?), dot: Bool) -> some View {
        if let w = parts.0 { Text(w).accessibilityIdentifier("today-weather") }
        if dot, parts.0 != nil, parts.1 != nil { Text("\u{00B7}").accessibilityHidden(true) }
        if let d = parts.1 { Text(d).accessibilityIdentifier("today-daylight") }
    }

    /* (weather words, daylight words) — each nil when unknown. */
    private func lineParts() -> (String?, String?) {
        guard let s = model.snapshot, s.day == store.today else { return (nil, nil) }
        let sun = Daylight.times(day: s.day, latitude: s.place.latitude, longitude: s.place.longitude)
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        var cal = Calendar.current; cal.timeZone = TimeZone.current

        // The session's hours when the plan gives a start, else the hours of daylight.
        var from = 8, to = 18
        if let sun {
            from = cal.component(.hour, from: sun.sunrise)
            to = cal.component(.hour, from: sun.sunset)
        }
        if let start = OutdoorSession.startTime(in: workout.source ?? [:]) {
            let length = Int(((Plan.plannedSeconds(workout, mapping) ?? 3600) / 3600).rounded(.up))
            from = start.hour; to = start.hour + max(1, length)
        }
        let weather = WeatherLine.text(s.hours, from: from, to: to)

        var daylight: String?
        if let sun {
            #if DEBUG
            let now = WeatherSwitch.fake ? Date(timeIntervalSince1970: (sun.sunrise.timeIntervalSince1970 + sun.sunset.timeIntervalSince1970) / 2) : Date()
            #else
            let now = Date()
            #endif
            if now < sun.sunrise { daylight = "Light from " + clock.string(from: sun.sunrise) }
            else if now < sun.sunset { daylight = "Light until " + clock.string(from: sun.sunset) }
        }
        return (weather, daylight)
    }
}

/* Settings: the one switch. The permission question comes only when Today first has an outdoor session and this is on. */
struct WeatherSettingsSection: View {
    @AppStorage(WeatherSwitch.key) private var on = true

    var body: some View {
        SectionHeading(text: "Weather")
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weather and daylight on Today").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Text("For an outdoor session: the forecast and when it gets dark. Your place is asked only when Today first needs it, and only a rounded place, about 10 km wide, is sent.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .tint(Theme.today)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityIdentifier("settings-weather-switch")
    }
}
