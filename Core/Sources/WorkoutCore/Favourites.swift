import Foundation

/*
 * Favourite sessions: small templates he keeps on the shelf (key "favourites",
 * one ordered list). A template is only WHAT a session is — sport, title,
 * words, planned length, zone — never a day, never anything he logged.
 * Pure rules here; the screens only call them.
 */
public struct FavouriteTemplate: Codable, Equatable, Identifiable {
    public var id: String
    public var sport: String
    public var title: String
    /* The description / steps text of the session. */
    public var purpose: String
    public var minutes: Double?
    /* Zone words, like "Z2" or "Z4–Z5". */
    public var zone: String

    public init(id: String = UUID().uuidString, sport: String, title: String, purpose: String = "",
                minutes: Double? = nil, zone: String = "") {
        self.id = id; self.sport = sport; self.title = title; self.purpose = purpose
        self.minutes = minutes; self.zone = zone
    }

    enum CodingKeys: String, CodingKey { case id, sport, title, purpose, minutes, zone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sport = try c.decodeIfPresent(String.self, forKey: .sport) ?? "other"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        minutes = try c.decodeIfPresent(Double.self, forKey: .minutes)
        zone = try c.decodeIfPresent(String.self, forKey: .zone) ?? ""
    }

    /* The session this template fills a form with: a day is given by the page, never kept here. */
    public func draft(on dayKey: String, isKey: Bool = false) -> SessionDraft {
        SessionDraft(dayKey: dayKey, sport: sport, title: title, minutes: minutes, intensity: zone,
                     purpose: purpose, isKey: isKey)
    }
}

public enum Favourites {
    public static let shelfKey = "favourites"
    public static let limit = 40
    /* Each template stays small: the shelf wants entries well under 2 KB. */
    static let titleLimit = 120
    static let purposeLimit = 500
    static let zoneLimit = 40

    /* A template made from a session's draft: trimmed and cut to size, no day. */
    public static func template(from draft: SessionDraft, id: String = UUID().uuidString) -> FavouriteTemplate {
        FavouriteTemplate(id: id, sport: draft.sport,
                          title: String(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(titleLimit)),
                          purpose: String(draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).prefix(purposeLimit)),
                          minutes: draft.minutes,
                          zone: String(draft.intensity.trimmingCharacters(in: .whitespacesAndNewlines).prefix(zoneLimit)))
    }

    /* "Already a favourite": the same sport and the same title, ignoring case, spacing and punctuation. */
    public static func isFavourite(sport: String, title: String, in list: [FavouriteTemplate]) -> Bool {
        let want = normalise(title)
        return list.contains { $0.sport == sport && normalise($0.title) == want }
    }

    /* Put at the end. False (nothing changed) when it is one already, has no title, or the list is full. */
    @discardableResult
    public static func add(_ template: FavouriteTemplate, to list: inout [FavouriteTemplate]) -> Bool {
        guard !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              list.count < limit,
              !isFavourite(sport: template.sport, title: template.title, in: list) else { return false }
        list.append(template)
        return true
    }

    /* A new name; an empty one changes nothing. */
    @discardableResult
    public static func rename(_ id: String, to name: String, in list: inout [FavouriteTemplate]) -> Bool {
        let words = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(titleLimit))
        guard !words.isEmpty, let i = list.firstIndex(where: { $0.id == id }) else { return false }
        list[i].title = words
        return true
    }

    public static func remove(_ id: String, from list: inout [FavouriteTemplate]) {
        list.removeAll { $0.id == id }
    }

    /* Dropped on another row: the dragged one takes that row's place, the rows between shift by one. */
    public static func move(_ id: String, onto target: String, in list: inout [FavouriteTemplate]) {
        guard id != target, let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == target }) else { return }
        let item = list.remove(at: from)
        list.insert(item, at: to)
    }
}
