import Foundation

/*
 * The no-gym version of a strength session (round 28, pick 20): a body-weight
 * circuit sized to the session's planned length. Text only: it changes nothing
 * in the plan; he logs the strength session as usual. Plain words, no medical
 * claims. Pure and fixed: the same minutes always give the same card.
 */

public struct NoGymMove: Equatable, Sendable {
    public let name: String
    /* "15 reps", "30 seconds" */
    public let amount: String
    /* Time the move takes, in seconds (counts for the length). */
    let seconds: Int
}

public struct NoGymCircuit: Equatable, Sendable {
    public let plannedMinutes: Int
    public let warmUp: String
    public let coolDown: String
    public let rounds: Int
    public let restSeconds: Int
    public let moves: [NoGymMove]
    let warmMinutes: Int
    let coolMinutes: Int

    /* The whole thing in minutes: warm-up, the rounds with their rests, cool-down. */
    public var totalMinutes: Double {
        let work = rounds * (moves.reduce(0) { $0 + $1.seconds } + moves.count * NoGymCircuit.transitionSeconds)
        let rests = max(0, rounds - 1) * restSeconds
        return Double(warmMinutes + coolMinutes) + Double(work + rests) / 60
    }

    static let transitionSeconds = 10
    static let all: [NoGymMove] = [
        NoGymMove(name: "Squats", amount: "15 reps", seconds: 45),
        NoGymMove(name: "Reverse lunges", amount: "8 reps each leg", seconds: 48),
        NoGymMove(name: "Push-ups", amount: "10 reps (knees down if needed)", seconds: 30),
        NoGymMove(name: "Glute bridge", amount: "15 reps, slow", seconds: 45),
        NoGymMove(name: "Plank", amount: "30 seconds", seconds: 30),
        NoGymMove(name: "Side plank", amount: "20 seconds each side", seconds: 40),
        NoGymMove(name: "Calf raises", amount: "20 reps", seconds: 40),
        NoGymMove(name: "Superman", amount: "12 reps, slow", seconds: 36)
    ]

    /*
     * About 20 minutes or less: six moves and a short warm-up; longer: all eight.
     * The number of rounds is the one that lands closest to the planned length.
     */
    public static func build(plannedMinutes: Int) -> NoGymCircuit {
        let planned = max(1, plannedMinutes)
        let long = planned > 25
        let moves = Array(all.prefix(long ? 8 : 6))
        let warm = planned >= 30 ? 5 : 3
        let rest = 60
        let warmUp = "Warm-up, \(warm) min: march on the spot, arm circles, leg swings, then 10 slow squats."
        let coolDown = "Cool-down, \(warm) min: walk slowly, then stretch calves, thighs, hips and chest; breathe slowly."
        var best: NoGymCircuit?
        for r in 1...8 {
            let c = NoGymCircuit(plannedMinutes: planned, warmUp: warmUp, coolDown: coolDown, rounds: r, restSeconds: rest,
                                 moves: moves, warmMinutes: warm, coolMinutes: warm)
            if r == 1 && planned >= 15 { best = c; continue }   // two rounds at least once there is time
            if best == nil || abs(c.totalMinutes - Double(planned)) < abs(best!.totalMinutes - Double(planned)) - 0.001 { best = c }
        }
        return best!
    }

    /* "3 rounds · 60 seconds rest between rounds" */
    public var roundsLine: String {
        "\(rounds) round\(rounds == 1 ? "" : "s") \u{00B7} \(restSeconds) seconds rest between rounds"
    }
}
