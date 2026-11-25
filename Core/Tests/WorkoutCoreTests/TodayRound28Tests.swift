import XCTest
@testable import WorkoutCore

/* Round 28, Today: daylight, the weather words, the week so far, the way back after illness. */
final class TodayRound28Tests: XCTestCase {

    private func minutesApart(_ a: Date, _ day: String, _ hhmm: String) -> Double {
        let p = hhmm.split(separator: ":").compactMap { Double($0) }
        let base = parseDayKey(day)!.timeIntervalSince1970   // midnight UTC of that day
        return abs(a.timeIntervalSince1970 - (base + (p[0] * 60 + p[1]) * 60)) / 60
    }

    /* Two known places and days (values as a public forecast gives them), within 3 minutes. */
    func testSunriseAndSunsetAtTwoKnownPlaces() throws {
        let stockholm = try XCTUnwrap(Daylight.times(day: "2026-12-02", latitude: 59.33, longitude: 18.07))
        XCTAssertLessThan(minutesApart(stockholm.sunrise, "2026-12-02", "07:19"), 3)
        XCTAssertLessThan(minutesApart(stockholm.sunset, "2026-12-02", "13:54"), 3)
        let london = try XCTUnwrap(Daylight.times(day: "2026-09-22", latitude: 51.51, longitude: -0.13))
        XCTAssertLessThan(minutesApart(london.sunrise, "2026-09-22", "05:46"), 3)
        XCTAssertLessThan(minutesApart(london.sunset, "2026-09-22", "17:59"), 3)
        // Polar night and polar day: no sunrise, no sunset.
        XCTAssertNil(Daylight.times(day: "2026-12-21", latitude: 69.65, longitude: 18.96))
        XCTAssertNil(Daylight.times(day: "2026-06-21", latitude: 69.65, longitude: 18.96))
    }

    func testWeatherWordsAndWhichSessionsAreOutdoor() {
        let hours = [WeatherHour(hour: 14, tempC: 11, feelsC: 7, windMs: 5, rainPercent: 10),
                     WeatherHour(hour: 15, tempC: 11, feelsC: 7, windMs: 5, rainPercent: 60),
                     WeatherHour(hour: 16, tempC: 11, feelsC: 7, windMs: 5, rainPercent: 70)]
        XCTAssertEqual(WeatherLine.text(hours, from: 14, to: 16), "11° · feels 7° · breezy 5 m/s · rain likely 15–16")
        XCTAssertEqual(WeatherLine.text([WeatherHour(hour: 9, tempC: 14, feelsC: 12, windMs: 1, rainPercent: 0)], from: 9, to: 10),
                       "14° · calm 1 m/s · dry")
        XCTAssertNil(WeatherLine.text(hours, from: 20, to: 21))
        XCTAssertTrue(OutdoorSession.isOutdoor(disciplineId: "run", text: "Easy run"))
        XCTAssertFalse(OutdoorSession.isOutdoor(disciplineId: "run", text: "Treadmill run"))
        XCTAssertFalse(OutdoorSession.isOutdoor(disciplineId: "swim", text: "Pool 2k"))
        XCTAssertTrue(OutdoorSession.isOutdoor(disciplineId: "swim", text: "Open water swim"))
        XCTAssertFalse(OutdoorSession.isOutdoor(disciplineId: "strength", text: "Core"))
    }

    private func session(_ day: String, _ sport: String, minutes: Double, logged: Bool = false) -> Workout {
        Workout(key: day + sport, sheet: "S", row: 1, rows: [1], date: parseDayKey(day)!, dayKey: day, disciplineRaw: sport,
                discipline: Discipline(id: sport, label: sport.capitalized, synonyms: []), title: "A session", phase: "",
                sections: [], planned: Planned(durationRaw: minutes, distanceRaw: nil, intensity: "", description: ""),
                results: [:], loggedInSheet: logged, missed: false, logged: logged)
    }

    /* Monday–Sunday, rest days out, a training extra counts as done only, an extra of an unplanned sport is left out. */
    func testWeekSoFarPerSport() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/plan", withExtension: "xlsx"))
        let mapping = try XCTUnwrap(try Plan.mapping(for: Workbook(data: try Data(contentsOf: url))))
        let unit = mapping.units.duration == "minutes" ? 1.0 : (mapping.units.duration == "hours" ? 1.0 / 60 : 1.0 / 1440)
        let plan = [session("2026-11-23", "run", minutes: 60 * unit, logged: true), session("2026-11-26", "run", minutes: 30 * unit),
                    session("2026-11-24", "bike", minutes: 90 * unit), session("2026-11-25", "rest", minutes: 60 * unit),
                    session("2026-11-30", "swim", minutes: 45 * unit)]   // next week
        let extras = [ExtraSummary(id: "a", dayKey: "2026-11-27", activity: "run", label: "Run", what: "", minutes: 20, isTraining: true, pending: false),
                      ExtraSummary(id: "b", dayKey: "2026-11-27", activity: "bike", label: "Bike", what: "", minutes: 50, isTraining: false, pending: false),
                      ExtraSummary(id: "c", dayKey: "2026-11-27", activity: "swim", label: "Swim", what: "", minutes: 30, isTraining: true, pending: false)]
        let sums = WeekSoFar.sums(plan: plan, extras: extras, mapping: mapping, today: "2026-11-25")
        XCTAssertEqual(sums.map(\.sport), ["bike", "run"])
        let run = try XCTUnwrap(sums.first { $0.sport == "run" })
        XCTAssertEqual(run.hours.planned, 90 * 60, accuracy: 1)
        XCTAssertEqual(run.hours.done, 60 * 60 + 20 * 60, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(sums.first { $0.sport == "bike" }).hours.done, 0, accuracy: 1)
    }

    /* Fever: rest, two easy days, week 1, week 2, back — the rule book's own steps, with the step he is on. */
    func testReturnStairsAreTheRuleBooksSteps() {
        var h = RBHealthTaps(illSince: "2026-11-01", illness: .belowNeck, symptomFreeSince: "2026-11-05")
        let s = ReturnLadder.stairs(health: h, settings: RuleBookSettings(), today: "2026-11-10")
        XCTAssertEqual(s.map(\.step), [.rest, .easyDays, .week1, .week2, .back])
        XCTAssertEqual(s.map(\.state), [.done, .done, .current, .ahead, .ahead])
        XCTAssertEqual(s[2].from, "2026-11-10")
        // Still ill: only the current stair has a start; the ones ahead have lengths, no dates.
        h.symptomFreeSince = nil
        let open = ReturnLadder.stairs(health: h, settings: RuleBookSettings(), today: "2026-11-03")
        XCTAssertEqual(open.first?.state, .current)
        XCTAssertEqual(open.first?.to, "")
        XCTAssertEqual(open.last?.from, "")
        XCTAssertTrue(ReturnLadder.stairs(health: RBHealthTaps(), settings: RuleBookSettings(), today: "2026-11-03").isEmpty)
    }
}
