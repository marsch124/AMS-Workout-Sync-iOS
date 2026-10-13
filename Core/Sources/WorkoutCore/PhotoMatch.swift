import Foundation

/*
 * Whether a photograph belongs to a session.
 *
 * It lives here, away from the screens, because it is arithmetic and because
 * getting it wrong is silent: the pictures simply are not drawn, and nothing
 * says why. That is what happened to him on 13 October 2026 — "Can not see
 * any photo thumbnails in the Today view".
 *
 * A photograph remembers the row it was taken against, and a row number is
 * not a name: insert a line in Excel and every row below it shifts, so
 * Weekly Schedules!7 becomes !8 and the pictures are orphaned everywhere at
 * once. The row is tried first, and failing that the day and the sport,
 * which a shifting row does not change.
 */
public enum PhotoMatch {
    public static func belongs(photoKey: String, photoDay: String, photoSport: String,
                               ownerKey: String, ownerDay: String, ownerSport: String) -> Bool {
        // An extra is keyed by what it is, not by a row, so it is exact.
        if ownerKey.hasPrefix("extra:") || photoKey.hasPrefix("extra:") {
            return photoKey == ownerKey
        }
        // The sport always has to agree: a row that has become another kind of
        // session is a different session, whatever its number says.
        guard photoSport == ownerSport else { return false }
        if photoKey == ownerKey { return true }
        return !photoDay.isEmpty && photoDay == ownerDay
    }
}
