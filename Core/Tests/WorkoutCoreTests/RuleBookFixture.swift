import XCTest
@testable import WorkoutCore

/*
 * An invented plan for the rule book's tests: same shape as a real 70.3 base
 * block (swim, two strength, bike quality, run quality, easy run, Friday rest,
 * long run Saturday, long ride Sunday; every fourth week easy), but made-up
 * dates (from Monday 7 January 2030), titles and minutes.
 */
struct Fixture {
    static let start = "2030-01-07"

    var sessions: [RBSession] = []
    var weeks: [RBWeek] = []
    var extras: [RBExtra] = []
    var feel = FeelLog()
    var settings = RuleBookSettings()
    var health = RBHealthTaps()
    var hurtDays: [String] = []
    var log: [SuggestionRecord] = []
    var importDay: String?
    private var row = 1

    static func day(_ week: Int, _ weekday: Int) -> String {
        PlanView.addDays(start, 7 * (week - 1) + weekday)
    }

    typealias Spec = (wd: Int, sport: RBSport, title: String, min: Int, zone: String, star: Bool)

    static func load(long ride: Int = 100, run: Int = 60, hardBike: Bool = false, hardRun: Bool = false) -> [Spec] {
        [(0, .swim, "Drill swim with pull sets", 45, "Z1–Z2", false),
         (0, .strength, "Strength A: main lifts", 35, "RPE 7", true),
         (1, .bike, "Trainer tempo blocks", 60, hardBike ? "Z3–Z4" : "Z2–Z3", true),
         (2, .run, "Run with short Z3 reps", 55, hardRun ? "Z3–Z4" : "Z2–Z3", false),
         (3, .strength, "Strength B: single leg and core", 30, "RPE 6", false),
         (3, .run, "Steady easy run with pickups", 40, "Z2", false),
         (4, .rest, "REST DAY", 0, "—", false),
         (6, .bike, "Long ride, even pace", ride, "Z2", true),
         (5, .run, "Long run, relaxed", run, "Z2", true)]
    }

    static func easy() -> [Spec] {
        [(0, .bike, "Spin, light gear", 45, "Z1–Z2", false),
         (1, .strength, "Strength, light day", 25, "RPE 4–5", false),
         (1, .run, "Gentle run, walking allowed", 35, "Z1–Z2", false),
         (2, .swim, "Relaxed drill swim", 40, "Z1–Z2", false),
         (3, .run, "Short shakeout run", 30, "Z1–Z2", false),
         (4, .rest, "REST DAY", 0, "—", false),
         (6, .bike, "Reduced long ride, chatty pace", 70, "Z1–Z2", false),
         (5, .run, "Reduced long run, relaxed", 45, "Z1–Z2", false)]
    }

    static func test() -> [Spec] {
        [(0, .run, "TEST — threshold run", 50, "Z4", true),
         (1, .swim, "TEST — swim time trial", 45, "Z4", true),
         (1, .strength, "Strength A: main lifts", 35, "RPE 7", true),
         (2, .bike, "TEST — bike threshold", 70, "Z4–Z5", true),
         (3, .strength, "Strength B: single leg and core", 30, "RPE 6", false),
         (3, .run, "Recovery jog after testing", 35, "Z1–Z2", false),
         (4, .rest, "REST DAY", 0, "—", false),
         (6, .bike, "Long ride, even pace", 90, "Z2", true),
         (5, .run, "Long run, relaxed", 55, "Z2", true)]
    }

    /* Weeks 1–3 load, 4 easy, 5 test, 6–7 load, 8 easy, 9–11 load, 12 easy, 13–14 load. */
    static func standard(longRides: [Int: Int] = [:], longRuns: [Int: Int] = [:]) -> Fixture {
        var f = Fixture()
        for w in 1...14 {
            switch w {
            case 4, 8, 12: f.addWeek(w, .easy, easy())
            case 5: f.addWeek(w, .test, test())
            default: f.addWeek(w, .load, load(long: longRides[w] ?? (90 + 2 * w), run: longRuns[w] ?? 60))
            }
        }
        return f
    }

    mutating func addWeek(_ number: Int, _ tag: RBWeekTag, _ specs: [Spec]) {
        weeks.append(RBWeek(number: number, monday: Fixture.day(number, 0), tag: tag, phase: number <= 8 ? "Base 1" : "Base 2"))
        for (i, s) in specs.enumerated() {
            sessions.append(RBSession(id: "w\(number)-\(i)", day: Fixture.day(number, s.wd), sport: s.sport, title: s.title,
                                      plannedMin: s.min, intensity: s.zone, star: s.star, phase: "Base", row: row,
                                      originalWeek: number))
            row += 1
        }
    }

    // MARK: logging

    mutating func index(_ id: String) -> Int { sessions.firstIndex { $0.id == id }! }
    func session(_ id: String) -> RBSession { sessions.first { $0.id == id }! }

    mutating func done(_ id: String, _ minutes: Int? = nil, rpe: Int? = nil) {
        let i = index(id)
        sessions[i].status = .done; sessions[i].actualMin = minutes ?? sessions[i].plannedMin; sessions[i].rpe = rpe
    }
    mutating func missed(_ id: String) { sessions[index(id)].status = .missed }
    mutating func move(_ id: String, to day: String) { sessions[index(id)].day = day }

    /* Everything dated before `day` done as planned (rest days aside). */
    mutating func allDone(before day: String) {
        for i in sessions.indices where sessions[i].day < day && !sessions[i].isRest && sessions[i].status == .open {
            sessions[i].status = .done; sessions[i].actualMin = sessions[i].plannedMin
        }
    }

    func id(_ week: Int, _ title: String) -> String {
        sessions.first { $0.originalWeek == week && $0.title.hasPrefix(title) }!.id
    }

    func input(_ today: String, _ moment: RBMoment = .morning) -> RuleBookInput {
        RuleBookInput(sessions: RuleBook.assignSlots(sessions), weeks: weeks, planStart: Fixture.start,
                      weekCaps: RuleBook.weekCaps(sessions), extras: extras, feel: feel, today: today, moment: moment,
                      log: log, health: health, hurtDays: hurtDays, importDay: importDay, settings: settings)
    }

    func suggest(_ today: String, _ moment: RBMoment = .morning) -> Suggestion? { RuleBook.suggest(input(today, moment)) }

    /* Every card a walk from → to would show, knowing only what was known each day. */
    func cards(from: String, to: String) -> [Suggestion] {
        RuleBook.replay(input(from), from: from, to: to).compactMap(\.outcome.suggestion)
    }
}

func limits(_ f: [LimitFailure]) -> [RBLimit] { f.map(\.limit) }
