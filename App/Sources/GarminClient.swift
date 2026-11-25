import Foundation
import WorkoutCore

/*
 * The part that talks to Garmin's free, read-only Personal API: the key is
 * handed in once, turned into an access token that lasts about a day (kept
 * in memory only), and the few GET calls below fetch the morning's numbers.
 * What Garmin answers is read by GarminMorning (Core), which forgives
 * anything missing.
 *
 * Nothing here ever prints, logs or returns the key; an error says what went
 * wrong in plain words and never what was sent.
 */
enum GarminFailure: Error, Equatable {
    case noKey
    case keyRefused     // Garmin did not accept the key
    case offline        // no connection, or Garmin did not answer
    case other

    var words: String {
        switch self {
        case .noKey: return "No key is saved."
        case .keyRefused: return "Garmin did not accept this key."
        case .offline: return "Could not reach Garmin. Try again in a moment."
        case .other: return "Garmin did not answer as expected."
        }
    }
}

actor GarminClient {
    static let shared = GarminClient()

    private static let base = "https://personal.connectapi.garmin.com"
    private static let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"

    private var token: (value: String, expires: Date)?
    private let session: URLSession

    init() {
        // Nothing kept on disk: no cache, no cookies.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    func forgetToken() { token = nil }

    // MARK: Token

    /* Asks Garmin for an access token with the saved key; throws when it will not give one. */
    @discardableResult
    func checkKey(_ key: String) async throws -> Date? {
        token = nil
        return try await mint(key: key).expires
    }

    private func mint(key: String) async throws -> (value: String, expires: Date) {
        guard let url = URL(string: Self.base + Self.tokenPath) else { throw GarminFailure.other }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // No Accept header on purpose: Garmin answers 406 when asked for JSON here.
        request.setValue("ApiKey " + key, forHTTPHeaderField: "Authorization")
        let (data, status) = try await send(request)
        if status == 401 || status == 403 { throw GarminFailure.keyRefused }
        guard (200..<300).contains(status) else { throw GarminFailure.other }
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // The answer is the bare token; tolerate a wrapped one.
        if text.hasPrefix("{"), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inner = (obj["access_token"] ?? obj["accessToken"] ?? obj["token"]) as? String {
            text = inner
        }
        guard !text.isEmpty else { throw GarminFailure.other }
        let expires = GarminMorning.tokenExpiry(text) ?? Date().addingTimeInterval(24 * 3600)
        let made = (text, expires)
        token = made
        return made
    }

    private func validToken() async throws -> String {
        if let token, token.expires.timeIntervalSinceNow > 5 * 60 { return token.value }
        guard let key = GarminKey.read() else { throw GarminFailure.noKey }
        return try await mint(key: key).value
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw GarminFailure.offline
        }
    }

    // MARK: Calls

    /* One GET, read as JSON. Nil when Garmin has nothing for it (no content, not found, odd answer). */
    func get(_ path: String, _ query: [String: String] = [:]) async throws -> Any? {
        var comps = URLComponents(string: Self.base + path)
        if !query.isEmpty { comps?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps?.url else { throw GarminFailure.other }
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue("Bearer " + (try await validToken()), forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, status) = try await send(request)
            if status == 401 {
                // The token may simply have run out: one fresh one, then give up.
                token = nil
                if attempt == 0 { continue }
                throw GarminFailure.keyRefused
            }
            if status == 403 { throw GarminFailure.keyRefused }
            guard (200..<300).contains(status), !data.isEmpty else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        return nil
    }

    /* A call whose failure only means "no number": the key and the connection still end the read. */
    private func tolerant(_ path: String, _ query: [String: String] = [:]) async throws -> Any? {
        do { return try await get(path, query) } catch let f as GarminFailure {
            if f == .noKey || f == .keyRefused || f == .offline { throw f }
            return nil
        }
    }

    /* This morning's numbers and the fortnight before them: six small reads. */
    func morning(day: String, bodyBatteryDays: [String: Double]) async throws -> MorningNumbers {
        let from = GarminMorning.addDays(day, -GarminMorning.fortnight)
        let before = GarminMorning.addDays(day, -1)
        let summary = try await tolerant("/usersummary-service/usersummary/daily", ["calendarDate": day])
        let sleep = try await tolerant("/sleep-service/sleep/dailySleep", ["date": day])
        let hrv = try await tolerant("/hrv-service/hrv/" + day)
        let hrvRange = try await tolerant("/hrv-service/hrv/daily/\(from)/\(before)")
        let sleepRange = try await tolerant("/sleep-service/sleep/dailySleepSummariesByDate", ["startDate": from, "endDate": day])
        let summaries = try await tolerant("/usersummary-service/v2/dailysummaries", ["startDate": from, "endDate": day])
        let byDay = GarminMorning.summaryDays(summaries)
        return GarminMorning.build(day: day, readAt: Date(),
                                   sleep: GarminMorning.sleep(sleep), hrv: GarminMorning.hrv(hrv),
                                   summary: GarminMorning.summary(summary),
                                   sleepDays: GarminMorning.sleepDays(sleepRange), hrvDays: GarminMorning.hrvDays(hrvRange),
                                   restingDays: byDay.resting, stressDays: byDay.stress,
                                   bodyBatteryDays: bodyBatteryDays)
    }
    /*
     * The Body page's numbers: six small reads, any one of which may fail
     * without losing the rest, and a seventh for yesterday's curve unless
     * the whole of it is already held (`yesterday`).
     */
    func body(day: String, yesterday held: [BodyDay.Point]? = nil, week heldWeek: [BodyDay.BatteryDay]? = nil) async throws -> BodyDay {
        let now = Date()
        let from = GarminMorning.addDays(day, -GarminBody.history)
        let weekAgo = GarminMorning.addDays(day, -(GarminBody.shownDays - 1))
        let nightDay = GarminMorning.morningDay(now: now)
        let curve = try await tolerant("/wellness-service/wellness/bodyBattery/reports/daily", ["startDate": day, "endDate": day])
        let workouts = try await tolerant("/activitylist-service/activities/search/activities",
                                          ["startDate": day, "endDate": day, "limit": "99", "start": "0"])
        let sleepRange = try await tolerant("/sleep-service/sleep/dailySleepSummariesByDate", ["startDate": weekAgo, "endDate": day])
        let hrvNight = try await tolerant("/hrv-service/hrv/" + nightDay)
        let hrvRange = try await tolerant("/hrv-service/hrv/daily/\(weekAgo)/\(day)")
        let summaries = try await tolerant("/usersummary-service/v2/dailysummaries", ["startDate": from, "endDate": day])
        var battery = GarminBody.battery(curve, activities: workouts, day: day, now: now)
        var week: [BodyDay.BatteryDay]?
        if let b = battery {
            if let held, !held.isEmpty, GarminBody.weekIsHeld(heldWeek, day: day) {
                // The days before today cannot change: only today's own curve is new.
                battery?.yesterday = held
                week = heldWeek
                week?[6] = GarminBody.batteryWeek(nil, day: day, todayPoints: b.points)[6]
            } else {
                // Today's own call stays exactly as it was; yesterday and the week before come from one report of seven days
                // (start = 6 days ago, end = today). Yesterday's thin line is cut from it, as before.
                let start = GarminMorning.addDays(day, -6)
                let old = try await tolerant("/wellness-service/wellness/bodyBattery/reports/daily", ["startDate": start, "endDate": day])
                let points = GarminBody.yesterday(old, day: day)
                battery?.yesterday = points.isEmpty ? nil : points
                let made = GarminBody.batteryWeek(old, day: day, todayPoints: b.points)
                week = made.dropLast().contains { !$0.points.isEmpty } ? made : nil
            }
        }
        return GarminBody.build(day: day, nightDay: nightDay, readAt: now,
                                battery: battery,
                                sleepDays: GarminBody.sleepDays(sleepRange),
                                hrv: GarminMorning.hrv(hrvNight), hrvDays: GarminBody.hrvDays(hrvRange),
                                summaries: GarminBody.summaryDays(summaries),
                                activity: GarminBody.activityDays(summaries), batteryWeek: week)
    }

    /*
     * The longer views' days (4 or 12 weeks), asked for only when he picks
     * one: sleep and HRV in pieces of at most 31 days (the Board's limit),
     * and one daily-summaries read for the rest. `from` is the first day
     * still missing; the caller keeps what is already held.
     */
    func history(from: String, to day: String) async throws -> BodyHistory {
        var h = BodyHistory()
        var s = from
        while s <= day {
            let e = min(GarminMorning.addDays(s, 30), day)
            let sleep = try await tolerant("/sleep-service/sleep/dailySleepSummariesByDate", ["startDate": s, "endDate": e])
            let hrv = try await tolerant("/hrv-service/hrv/daily/\(s)/\(e)")
            h.sleep.merge(GarminBody.sleepDays(sleep)) { _, new in new }
            h.hrv.merge(GarminBody.hrvDays(hrv)) { _, new in new }
            s = GarminMorning.addDays(e, 1)
        }
        let summaries = try await tolerant("/usersummary-service/v2/dailysummaries", ["startDate": from, "endDate": day])
        let d = GarminBody.summaryDays(summaries)
        let a = GarminBody.activityDays(summaries)
        h.resting = d.resting; h.stress = d.stressAverage; h.steps = a.steps; h.intensity = a.intensity
        return h
    }
}
