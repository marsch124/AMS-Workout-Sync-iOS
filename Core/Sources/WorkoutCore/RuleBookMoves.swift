import Foundation

/*
 * The move menu (spec 1.2): the ONLY changes the rule book — or an AI asked
 * to pick for it — can ever propose. Each one is applied to a copy of the
 * plan; the limits then judge the copy.
 */

public enum RBSubstitute: String, Codable, Equatable, Sendable {
    /* "Row instead, same minutes, Z1–Z2" (his guide B17, B21). */ case row
    /* "An easy spin instead" (B21). */ case easySpin
}

public enum Move: Codable, Equatable, Sendable {
    /* M1 · status → changed, minutes 0, shown as "rest (your choice)". */
    case drop(session: String)
    /* M2 · exchange days with the first later EASY session of the same plan week. */
    case swapWithNextEasy(session: String, easy: String)
    /* M3 · planned minutes → `minutes` (N % of plan rounded to 5, or T4's step). */
    case shorten(session: String, minutes: Int)
    /* M4 · zone down to Z1–Z2 ("RPE 4–5, fewer sets" for strength); optionally as a row or an easy spin.
       OPEN: the substitute is not in the spec's menu table but in its G11/G13 "Other choice" lines. */
    case makeEasier(session: String, instead: RBSubstitute?)
    /* M5 · a new day in the same plan week, never a Friday. */
    case moveToDay(session: String, day: String)
    /* M6 · the next 7 days take the session list of easy week `easyWeek`. */
    case bringEasyWeekForward(from: String, easyWeek: Int)
    /* M7 · M1 on every session of one day. */
    case extraRestDay(day: String)

    public var code: String {
        switch self {
        case .drop: return "M1"
        case .swapWithNextEasy: return "M2"
        case .shorten: return "M3"
        case .makeEasier: return "M4"
        case .moveToDay: return "M5"
        case .bringEasyWeekForward: return "M6"
        case .extraRestDay: return "M7"
        }
    }

    /* The sessions a move names directly (M6 and M7 resolve theirs on the plan). */
    public var sessionIDs: [String] {
        switch self {
        case .drop(let s), .shorten(let s, _), .makeEasier(let s, _), .moveToDay(let s, _): return [s]
        case .swapWithNextEasy(let s, let e): return [s, e]
        case .bringEasyWeekForward, .extraRestDay: return []
        }
    }

    var droppedIDs: [String] {
        if case .drop(let s) = self { return [s] }
        return []
    }
}

public enum RuleBookMoveError: Error, Equatable {
    case noSession(String)
    case notAllowed(String)
}

extension RuleBook {
    public static let easyIntensity = "Z1–Z2"
    public static let easyStrength = "RPE 4–5, fewer sets"
    public static let easyPrefix = "Easy version: "

    /* N % of the plan, rounded to the nearest 5. */
    public static func percent(_ minutes: Int, _ n: Int) -> Int { roundTo5(Double(minutes) * Double(n) / 100) }

    /*
     * The plan after the moves, as a copy. Moves that name a session that is
     * not there throw; the limits judge everything else.
     */
    public static func apply(_ moves: [Move], to plan: [RBSession], input: RuleBookInput) throws -> [RBSession] {
        var out = plan
        func index(_ id: String) throws -> Int {
            guard let i = out.firstIndex(where: { $0.id == id }) else { throw RuleBookMoveError.noSession(id) }
            return i
        }
        func drop(_ i: Int) { out[i].dropped = true; out[i].status = .changed }
        for move in moves {
            switch move {
            case .drop(let id):
                drop(try index(id))
            case .swapWithNextEasy(let id, let easy):
                let a = try index(id), b = try index(easy)
                let day = out[a].day
                out[a].day = out[b].day; out[b].day = day
                out[a].status = out[a].status == .missed ? .changed : out[a].status
            case .shorten(let id, let minutes):
                let i = try index(id)
                out[i].plannedMin = minutes
                out[i].status = .changed
            case .makeEasier(let id, let instead):
                let i = try index(id)
                if out[i].sport == .strength {
                    out[i].intensity = easyStrength
                } else if (zones(out[i].intensity).top ?? 9) > 1 {
                    out[i].intensity = easyIntensity
                }
                if let instead {
                    out[i].sport = instead == .row ? .other : .bike
                    out[i].title = instead == .row ? "Row, same minutes" : "Easy spin, same minutes"
                }
                if !out[i].title.hasPrefix(easyPrefix) { out[i].title = easyPrefix + out[i].title }
                out[i].star = false
                out[i].status = .changed
            case .moveToDay(let id, let day):
                let i = try index(id)
                out[i].day = day
                out[i].status = .changed
            case .extraRestDay(let day):
                for i in out.indices where out[i].day == day && !out[i].isRest { drop(i) }
            case .bringEasyWeekForward(let from, let easyWeek):
                out = try bringForward(out, from: from, easyWeek: easyWeek, input: input)
            }
        }
        return out
    }

    /*
     * M6: the next 7 days (from `from`) take the easy week's sessions, each on
     * the same weekday; what was there is dropped, not made up. With Q3 on the
     * later easy week stays as it is; with Q3 off it takes the dropped sessions.
     */
    static func bringForward(_ plan: [RBSession], from: String, easyWeek: Int, input: RuleBookInput) throws -> [RBSession] {
        var out = plan
        let easyMonday = input.monday(of: easyWeek)
        // The next 7 days, but never into the easy week itself.
        let days = (0..<7).map { PlanView.addDays(from, $0) }.filter { $0 < easyMonday }
        let easyDays = Set((0..<7).map { PlanView.addDays(easyMonday, $0) })
        let easySessions = plan.filter { easyDays.contains($0.day) && $0.counts }
        guard !easySessions.isEmpty else { throw RuleBookMoveError.notAllowed("no easy week \(easyWeek)") }
        let replaced = plan.filter { days.contains($0.day) && $0.counts && $0.status == .open }
        for i in out.indices where replaced.contains(where: { $0.id == out[i].id }) {
            out[i].dropped = true; out[i].status = .changed
        }
        for e in easySessions {
            let wd = weekday(e.day)
            guard let day = days.first(where: { weekday($0) == wd }) else { continue }
            var copy = e
            copy.id = e.id + "@forward"
            copy.day = day
            copy.status = .open
            copy.addedByMove = true
            copy.originalWeek = input.week(of: day)
            out.append(copy)
        }
        if !input.settings.laterEasyWeekStaysEasy {
            for i in out.indices where easyDays.contains(out[i].day) && out[i].counts && !out[i].addedByMove { out[i].dropped = true; out[i].status = .changed }
            for r in replaced {
                let wd = weekday(r.day)
                guard let day = easyDays.first(where: { weekday($0) == wd }) else { continue }
                var copy = r
                copy.id = r.id + "@later"
                copy.day = day
                copy.status = .open
                copy.addedByMove = true
                copy.originalWeek = easyWeek
                out.append(copy)
            }
        }
        return out.sorted { ($0.day, $0.row) < ($1.day, $1.row) }
    }
}
