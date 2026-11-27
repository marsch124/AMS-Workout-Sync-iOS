import Foundation

/*
 * Drill cards (round 30, pick 16): each swim drill and each strength or mobility
 * exercise the app names, as a drawing, three steps and one line about what it
 * trains. This file is the pure part: the cards, the drawings as plain data, and
 * the reading of a session's words ("4x50 catch-up, then 4x50 fist") to find the
 * cards that fit it.
 *
 * A drawing is a few lines in a small drawing language, on a box 36 wide and
 * 24 high (the icon library's 24-point grid, one and a half squares wide):
 *   L x y x y …   a line through the points, round ends and joins
 *   C x y r       a circle (a head, a fist, a weight)
 *   W y           the water: a gentle wave across the box at height y
 * The app draws every line with one even stroke of 1.9 on that grid.
 */

public enum DrillKind: String, Codable, Sendable, CaseIterable {
    case swim, strength, mobility
}

public struct DrillArt: Equatable, Sendable {
    public var lines: [[Double]] = []
    public var circles: [[Double]] = []
    public var waves: [Double] = []

    public static let width = 36.0
    public static let height = 24.0
    public static let stroke = 1.9

    /* Reads the drawing language; anything it does not understand is left out. */
    public init(_ text: String) {
        for part in text.split(separator: ";") {
            let words = part.split(separator: " ").map(String.init)
            guard let head = words.first else { continue }
            let nums = words.dropFirst().compactMap(Double.init)
            guard nums.count == words.count - 1 else { continue }
            switch head {
            case "L": if nums.count >= 4, nums.count % 2 == 0 { lines.append(nums) }
            case "C": if nums.count == 3 { circles.append(nums) }
            case "W": if nums.count == 1 { waves.append(nums[0]) }
            default: break
            }
        }
    }

    /* Every point and circle lies inside the box (with room for the stroke). */
    public var fitsTheBox: Bool {
        let pad = DrillArt.stroke / 2
        for l in lines {
            for i in stride(from: 0, to: l.count, by: 2) where l[i] < pad || l[i] > Self.width - pad || l[i + 1] < pad || l[i + 1] > Self.height - pad { return false }
        }
        for c in circles where c[0] - c[2] < pad || c[0] + c[2] > Self.width - pad || c[1] - c[2] < pad || c[1] + c[2] > Self.height - pad { return false }
        return !lines.isEmpty
    }
}

public struct DrillCard: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: DrillKind
    public let steps: [String]
    public let trains: String
    /* The words a session may use for it, in plain lower case ("catch up" for "Catch-up"). */
    public let keys: [String]
    public let art: String

    public var drawing: DrillArt { DrillArt(art) }
}

public enum DrillCards {
    /* The swimmer, side view, moving right: one straight body line just under the water,
       the lower leg kicked a little, the head at the water line. The arms come from the shoulder at 22 13. */
    private static let swimmer = "W 9.5; L 3 13 24.6 13; L 11 13 3.4 15.8; C 28.4 10.6 2.1"
    /* One arm reaching forward under the water, and one swinging forward over it. */
    private static let reach = "L 22 13 34 17"
    private static let armOver = "L 22 13 21 5 28.4 3.4"
    /* The swimmer on the side: the lower arm straight ahead, the head resting on it, legs kicking. */
    private static let onSide = "W 9.2; L 3.4 11.6 9 14 22 14 35 14; L 9 14 3.4 16.6; C 26.6 10.2 2.1"
    private static let ground = "L 3 23 33 23"

    public static let all: [DrillCard] = [
        DrillCard(id: "catch-up", name: "Catch-up", kind: .swim,
                  steps: ["Stretch both arms out in front, one hand on top of the other.",
                          "Pull with one arm while the other waits out in front.",
                          "Touch hands again before the other arm starts."],
                  trains: "A long reach and patience in the glide.",
                  keys: ["catch up", "catchup"],
                  art: swimmer + "; L 22 13 34.6 15.6; L 22 13 34.2 18.6"),
        DrillCard(id: "fingertip-drag", name: "Fingertip drag", kind: .swim,
                  steps: ["Swim easy freestyle with a relaxed arm.",
                          "Keep your elbow high and let your fingertips skim the water.",
                          "Reach forward and enter the water ahead of your shoulder."],
                  trains: "A high elbow and a relaxed arm recovery.",
                  keys: ["fingertip drag", "finger tip drag", "fingertip"],
                  art: swimmer + "; " + reach + "; L 22 13 18.5 4.2 23.6 8.8"),
        DrillCard(id: "fist", name: "Fist", kind: .swim,
                  steps: ["Swim easy freestyle with both hands closed in loose fists.",
                          "Keep your elbows high and pull with the whole forearm.",
                          "After 25 m open your hands and feel the extra grip."],
                  trains: "Pulling with the forearm, not only the hand.",
                  keys: ["fist"],
                  art: swimmer + "; L 22 13 32.4 16.4; C 33.8 16.9 0.9; L 22 13.4 26.4 18.6 22 21.2; C 20.6 21.6 0.9"),
        DrillCard(id: "single-arm", name: "Single arm", kind: .swim,
                  steps: ["Rest one arm at your side.",
                          "Swim with the other arm only, and roll your body with each pull.",
                          "Swap arms every length."],
                  trains: "One clean pull at a time, and body rotation.",
                  keys: ["single arm", "one arm"],
                  art: swimmer + "; " + armOver + "; L 22 13 19.8 15.6 13 15.6"),
        DrillCard(id: "side-kick", name: "Kick on the side", kind: .swim,
                  steps: ["Lie on your side with the lower arm stretched out in front.",
                          "Rest the top arm on your hip and your head on the lower arm.",
                          "Kick from the hips with small, quick kicks."],
                  trains: "Balance on your side and a steady kick.",
                  keys: ["side kick", "kick on the side", "kick on side", "kick on your side", "side kicking"],
                  art: onSide + "; L 22 14 13 11.4"),
        DrillCard(id: "six-one-six", name: "6-1-6", kind: .swim,
                  steps: ["Kick six times on your side with one arm out in front.",
                          "Take one stroke and roll to your other side.",
                          "Kick six times on that side, then repeat."],
                  trains: "Rotation and timing between strokes.",
                  keys: ["6 1 6", "616", "six kick switch", "6 kick switch"],
                  art: onSide + "; L 22 14 20.6 5.6 27.8 3.4"),
        DrillCard(id: "sculling", name: "Sculling", kind: .swim,
                  steps: ["Stretch both arms out in front, palms facing down.",
                          "Sweep your hands out and in, drawing a thin figure of eight.",
                          "Keep your elbows high and feel the water on your palms."],
                  trains: "A feel for the water.",
                  keys: ["scull", "sculling", "sculls"],
                  art: swimmer + "; L 22 13 30.8 16.2; L 25.4 20.4 34.4 20.4; L 27.2 18.6 25.4 20.4 27.2 22.2; L 32.6 18.6 34.4 20.4 32.6 22.2"),
        DrillCard(id: "zipper", name: "Zipper", kind: .swim,
                  steps: ["Swim easy freestyle.",
                          "As your hand leaves the water, run your thumb up your side from hip to armpit, as if closing a zip.",
                          "Then reach forward and enter the water."],
                  trains: "A high elbow and a short, relaxed recovery.",
                  keys: ["zipper", "zip"],
                  art: swimmer + "; " + reach + "; L 22 13 18.8 5 20.6 11.4; L 12 11.5 12 14.5; L 14.8 11.5 14.8 14.5; L 17.6 11.5 17.6 14.5"),
        DrillCard(id: "pull-buoy", name: "Pull buoy", kind: .swim,
                  steps: ["Hold the buoy between your thighs.",
                          "Swim freestyle with a steady pull, keeping your hips high.",
                          "Breathe every third stroke to stay balanced."],
                  trains: "Pulling strength and body position.",
                  keys: ["pull buoy", "buoy"],
                  art: "W 9.5; L 3 13 8.4 13; L 15.6 13 24.6 13; C 28.4 10.6 2.1; " + reach + "; " + armOver + "; L 9.2 11 14.8 11 15.6 11.8 15.6 14.6 14.8 15.4 9.2 15.4 8.4 14.6 8.4 11.8 9.2 11"),
        DrillCard(id: "head-up", name: "Head-up swim", kind: .swim,
                  steps: ["Swim freestyle and look forward, with the water at your hairline.",
                          "Keep your hands strong and your stroke quick.",
                          "After 4 to 8 strokes, put your face back in."],
                  trains: "Sighting in open water and a strong pull.",
                  keys: ["head up", "tarzan", "water polo"],
                  art: "W 11.5; L 3 14.5 22.6 14.5 24.6 11.6; L 11 14.5 3.4 17.2; C 26.6 8.6 2.1; L 22.6 14.5 34 18; L 22.6 14.5 26.6 19.8 22.4 22.2"),

        DrillCard(id: "squats", name: "Squats", kind: .strength,
                  steps: ["Stand with your feet shoulder-width apart, toes slightly out.",
                          "Sit your hips back and down, chest up, knees over your toes.",
                          "Push through your whole foot to stand tall."],
                  trains: "Legs and hips, for the bike and the run.",
                  keys: ["squat", "air squat", "bodyweight squat"],
                  art: ground + "; C 18.5 5 2.2; L 13 15 17 8; L 13 15 20 15 18 22.5; L 18 22.5 22 22.5; L 17 9 25 9"),
        DrillCard(id: "reverse-lunges", name: "Reverse lunges", kind: .strength,
                  steps: ["Stand tall with your hands on your hips.",
                          "Step back with one foot and lower until both knees bend.",
                          "Push through the front foot to come back, then swap legs."],
                  trains: "Single-leg strength and balance.",
                  keys: ["reverse lunge", "lunge", "split squat"],
                  art: ground + "; C 18 4.5 2.2; L 18 7 18 13; L 18 13 23 15 23 22.5; L 18 13 13 19 6 22; L 18 8.5 15 11 18 12.5"),
        DrillCard(id: "push-ups", name: "Push-ups", kind: .strength,
                  steps: ["Put your hands under your shoulders, body in one long line.",
                          "Lower your chest towards the floor, elbows at about 45 degrees.",
                          "Press back up. Drop to your knees if you need to."],
                  trains: "Chest, shoulders and arms, for the swim.",
                  keys: ["push up", "pushup", "press up"],
                  art: ground + "; L 5 22 27 12.5; C 30.5 10.5 2.2; L 27 12.5 27.5 22"),
        DrillCard(id: "glute-bridge", name: "Glute bridge", kind: .strength,
                  steps: ["Lie on your back with your knees bent and feet flat.",
                          "Press through your heels and lift your hips.",
                          "Pause at the top, then lower slowly."],
                  trains: "Glutes and hamstrings, the engine of the run and the ride.",
                  keys: ["glute bridge", "bridge", "hip bridge"],
                  art: ground + "; C 3.5 21 1.9; L 7 21.5 16 14 25 10 27 22.5; L 7 22 14 22"),
        DrillCard(id: "plank", name: "Plank", kind: .strength,
                  steps: ["Rest on your forearms with your elbows under your shoulders.",
                          "Make one straight line from your head to your heels.",
                          "Hold, breathing evenly, then lower."],
                  trains: "A steady core.",
                  keys: ["plank"],
                  art: ground + "; L 4 22.5 26 14.5; C 29.8 13 2.2; L 26 14.5 26 22 31.5 22"),
        DrillCard(id: "side-plank", name: "Side plank", kind: .strength,
                  steps: ["Lie on one side, elbow under your shoulder, feet stacked.",
                          "Lift your hips so your body makes a straight line.",
                          "Hold, then swap sides."],
                  trains: "Side core and hip stability.",
                  keys: ["side plank"],
                  art: ground + "; L 5 22 23 13.5; C 26.5 11.7 2.2; L 23 13.5 23 22 29 22; L 23 13.5 22 5"),
        DrillCard(id: "calf-raises", name: "Calf raises", kind: .strength,
                  steps: ["Stand tall, with a wall or chair for balance.",
                          "Rise slowly onto your toes.",
                          "Pause, then lower slowly."],
                  trains: "Calves and ankles, for running.",
                  keys: ["calf raise", "heel raise"],
                  art: ground + "; C 16 3.6 2; L 16 6.6 16 14.6 16.4 20 19 22.1; L 16 9 21.6 12.6; L 16 9 10.4 12.6; L 26 19.4 26 10.4; L 23.8 12.6 26 10.4 28.2 12.6"),
        DrillCard(id: "superman", name: "Superman", kind: .strength,
                  steps: ["Lie face down with your arms stretched out in front.",
                          "Lift your arms, chest and legs a little off the floor.",
                          "Hold for a second, then lower slowly."],
                  trains: "Back muscles, for posture on the bike and in the water.",
                  keys: ["superman"],
                  art: ground + "; L 3 16.6 14 21 22.4 18.4 34.4 12.4; C 26 13 2.1"),

        DrillCard(id: "hamstring-stretch", name: "Hamstring stretch", kind: .mobility,
                  steps: ["Lie on your back and loop a towel round one foot.",
                          "Lift that leg, keeping it nearly straight.",
                          "Hold for 30 seconds with easy breaths, then swap."],
                  trains: "Loose hamstrings.",
                  keys: ["hamstring", "hamstring stretch"],
                  art: ground + "; C 3.5 21 1.9; L 6 21.8 18 21.8 31 21.8; L 18 21.8 24 7.5; L 8 21 22 9"),
        DrillCard(id: "calf-stretch", name: "Calf stretch", kind: .mobility,
                  steps: ["Stand facing a wall with your hands on it.",
                          "Step one foot back, keeping the heel on the floor.",
                          "Lean in, hold for 30 seconds, then swap."],
                  trains: "Loose calves.",
                  keys: ["calf stretch", "calf", "calve"],
                  art: ground + "; L 30 1.5 30 23; L 8 22.5 17 12.5 23 7; C 25 5 2.1; L 23 7.5 29 8.5; L 17 12.5 23 17.5 22 22.5"),
        DrillCard(id: "open-book", name: "Open book", kind: .mobility,
                  steps: ["Lie on your side with your knees bent and arms out in front.",
                          "Open your top arm up and back, following it with your eyes.",
                          "Come back slowly. Do 8 on each side."],
                  trains: "Upper-back movement, for the swim and the bike position.",
                  keys: ["open book", "t spine", "tspine", "thoracic", "upper back"],
                  art: ground + "; L 12 20.1 33.6 20.1; C 28 16.2 2; L 23.5 20.1 23.5 9.4 17.2 6.4; L 12 20.1 7 15.6 3.4 20.1"),
        DrillCard(id: "hip-flexor-stretch", name: "Hip flexor stretch", kind: .mobility,
                  steps: ["Kneel on one knee with the other foot in front.",
                          "Tuck your tailbone and press your hips gently forward.",
                          "Hold for 30 seconds, then swap."],
                  trains: "Open hips, after long rides.",
                  keys: ["hip flexor", "hip flexors", "hip", "hips", "hip opener"],
                  art: ground + "; C 16 4 2; L 16 6.5 16 14; L 16 14 23 14.5 23 22.5; L 16 14 14 22.5 6 22.5"),
        DrillCard(id: "hip-hinge", name: "Hip hinge", kind: .strength,
                  steps: ["Stand tall with your feet hip-width apart and soft knees.",
                          "Push your hips back and tip forward with a flat back.",
                          "Squeeze your glutes to stand tall again."],
                  trains: "The movement behind strong, safe lifting and riding.",
                  keys: ["hip hinge", "hinge", "deadlift", "good morning"],
                  art: ground + "; L 12 12 14.5 17.5 15 22.5; L 12 12 24 9.5; C 27.5 9 2.2; L 24 10 24 18; C 24 19.4 1.4"),
        DrillCard(id: "row", name: "Row", kind: .strength,
                  steps: ["Hinge forward with a flat back and a weight or band in one hand.",
                          "Pull your elbow back past your ribs.",
                          "Lower slowly. Do all the reps, then swap arms."],
                  trains: "Upper back and pulling muscles.",
                  keys: ["row", "bent over row", "band row"],
                  art: ground + "; L 12 12 14.5 17.5 15 22.5; L 12 12 24 9.5; C 27.5 9 2.2; L 23 10 18 11 21 16; C 21.4 17.6 1.4"),
    ]

    public static func card(_ id: String) -> DrillCard? { all.first { $0.id == id } }
    public static func cards(of kind: DrillKind) -> [DrillCard] { all.filter { $0.kind == kind } }

    // MARK: finding the cards a session names

    /* Lower-case words: letters and digits only, a plural s taken off ("drills" and "drill" match). */
    static func words(_ text: String) -> [String] {
        var out: [String] = [], word = ""
        func flush() {
            guard !word.isEmpty else { return }
            if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { word.removeLast() }
            out.append(word); word = ""
        }
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber { word.append(ch) } else { flush() }
        }
        flush()
        return out
    }

    /* A word that was said but is not a card: the general "drill" of a swim session. */
    public static func mentionsDrillsInGeneral(_ text: String) -> Bool {
        words(text).contains("drill")
    }

    /*
     * The cards a session's words name, in the order of the cards. Swim sessions
     * find swim drills; strength and mobility sessions find exercises and
     * stretches; every other sport finds none. The longest phrase is found
     * first and its words are used up, so "side plank" never also finds "plank".
     */
    public static func matches(in text: String, discipline: String) -> [DrillCard] {
        let kinds: Set<DrillKind>
        switch discipline {
        case "swim": kinds = [.swim]
        case "strength", "mobility": kinds = [.strength, .mobility]
        default: return []
        }
        var tokens: [String?] = words(text).map { Optional($0) }
        let phrases: [(phrase: [String], card: DrillCard)] = all.filter { kinds.contains($0.kind) }
            .flatMap { c in c.keys.map { (words($0), c) } }
            .sorted { $0.phrase.count > $1.phrase.count }
        var found = Set<String>()
        for (phrase, card) in phrases where !phrase.isEmpty && phrase.count <= tokens.count {
            var i = 0
            while i + phrase.count <= tokens.count {
                if (0..<phrase.count).allSatisfy({ tokens[i + $0] == phrase[$0] }) {
                    found.insert(card.id)
                    for k in 0..<phrase.count { tokens[i + k] = nil }
                    i += phrase.count
                } else { i += 1 }
            }
        }
        return all.filter { found.contains($0.id) }
    }

    /* The words on the row: "Drill cards: Catch-up, Fist". */
    public static func rowWords(_ cards: [DrillCard]) -> String {
        "Drill cards: " + cards.map(\.name).joined(separator: ", ")
    }
}
