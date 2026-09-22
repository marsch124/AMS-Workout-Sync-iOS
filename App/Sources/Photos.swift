import Foundation
import SwiftUI
import UIKit
import WorkoutCore

/*
 * Photographs attached to a session, or to an extra. The web app's rules,
 * kept whole:
 *
 *   - They never go into the workbook (invariant 7). A picture lives on the
 *     phone beside the plan, and the app says so. Here that is Application
 *     Support, which the iPhone's own backup includes — the web app's storage
 *     was not, which is one of the reasons for this app.
 *   - Attribution follows the move-log rule: a session's identity is sheet +
 *     row, so the sport a photo was taken against has to still agree, or the
 *     photo is not shown against that session. It is not lost: orphans are
 *     counted in Settings and go into the export.
 *   - An extra is identified by day + activity + length, exactly as the
 *     writer recognises one (Extras.keyFor), so no sport guard there.
 *   - 1600 on the long edge, JPEG at 0.72: a phone photograph at roughly
 *     250 KB, still sharper than the screen it is looked at on.
 */
struct PhotoMeta: Codable, Identifiable, Equatable {
    let id: String
    let workoutKey: String
    let disciplineId: String
    let dayKey: String
    let title: String
    let sheet: String
    let kind: String            // session | extra
    let addedAt: Date
    let bytes: Int
    let type: String
    let width: Int
    let height: Int
}

/* What a photograph can hang on: a session or an extra. */
struct PhotoOwner {
    let key: String
    let disciplineId: String
    let dayKey: String
    let title: String
    let sheet: String

    init(_ w: Workout) {
        key = w.key; disciplineId = w.discipline.id; dayKey = w.dayKey; title = w.title; sheet = w.sheet
    }

    init(extra x: ExtraSummary) {
        key = Extras.keyFor(date: x.dayKey, label: x.label, minutes: x.minutes)
        disciplineId = x.activity; dayKey = x.dayKey; title = x.what.isEmpty ? x.label : x.what; sheet = ""
    }
}

@MainActor
final class PhotoStore: ObservableObject {
    static let shared = PhotoStore()
    static let maxEdge: CGFloat = 1600
    static let quality: CGFloat = 0.72

    @Published private(set) var index: [PhotoMeta] = []

    private var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    init() {
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([PhotoMeta].self, from: data) {
            index = saved.sorted { $0.addedAt < $1.addedAt }
        }
        #if DEBUG
        if let key = ProcessInfo.processInfo.environment["AMSWS_FAKE_PHOTOS"], index.isEmpty {
            let owner = PhotoOwner(key: key, disciplineId: ProcessInfo.processInfo.environment["AMSWS_FAKE_SPORT"] ?? "run",
                                   dayKey: "2026-09-12", title: "Long run", sheet: "Weekly Schedules")
            for hue in [0.55, 0.1] {
                let img = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
                    UIColor(hue: hue, saturation: 0.5, brightness: 0.8, alpha: 1).setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
                    UIColor.white.setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: 400, y: 250, width: 400, height: 400))
                }
                if let data = img.jpegData(compressionQuality: 0.9) { add(data, to: owner) }
            }
        }
        #endif
    }

    private func saveIndex() {
        try? JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    func belongsTo(_ photo: PhotoMeta, _ owner: PhotoOwner) -> Bool {
        guard photo.workoutKey == owner.key else { return false }
        if owner.key.hasPrefix("extra:") { return true }
        return photo.disciplineId == owner.disciplineId
    }

    func photos(for owner: PhotoOwner) -> [PhotoMeta] { index.filter { belongsTo($0, owner) } }
    func count(for owner: PhotoOwner) -> Int { photos(for: owner).count }
    var totalBytes: Int { index.reduce(0) { $0 + $1.bytes } }

    func orphans(owners: [PhotoOwner]) -> [PhotoMeta] {
        index.filter { photo in !owners.contains { belongsTo(photo, $0) } }
    }

    func url(_ id: String) -> URL { folder.appendingPathComponent(id + ".jpg") }
    func data(_ id: String) -> Data? { try? Data(contentsOf: url(id)) }
    func image(_ id: String) -> UIImage? { data(id).flatMap(UIImage.init(data:)) }

    /* Shrunk, or kept as it came if shrinking would not make it smaller. */
    static func shrink(_ original: Data) -> (data: Data, width: Int, height: Int) {
        guard let image = UIImage(data: original) else { return (original, 0, 0) }
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let out = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // Drawing through UIImage honours the EXIF orientation, so a portrait
        // photograph does not arrive on its side.
        let drawn = UIGraphicsImageRenderer(size: out, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: out)) }
        guard let jpeg = drawn.jpegData(compressionQuality: quality), jpeg.count < original.count else {
            return (original, Int(size.width), Int(size.height))
        }
        return (jpeg, Int(out.width), Int(out.height))
    }

    @discardableResult
    func add(_ original: Data, to owner: PhotoOwner) -> PhotoMeta? {
        let shrunk = Self.shrink(original)
        let id = "p" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 0..<1_679_616), radix: 36)
        do { try shrunk.data.write(to: url(id), options: .atomic) } catch { return nil }
        let meta = PhotoMeta(id: id, workoutKey: owner.key, disciplineId: owner.disciplineId, dayKey: owner.dayKey,
                             title: owner.title, sheet: owner.sheet, kind: owner.key.hasPrefix("extra:") ? "extra" : "session",
                             addedAt: Date(), bytes: shrunk.data.count, type: "image/jpeg", width: shrunk.width, height: shrunk.height)
        index.append(meta)
        saveIndex()
        return meta
    }

    /*
     * A photograph follows its extra when the extra is corrected.
     *
     * An extra is named by its day, its activity and its length — the way the
     * writer recognises one — so changing any of those three gives it a new
     * name, and pictures left under the old one would belong to nothing. They
     * are not lost when that happens (orphans are counted and exported), but
     * "shown nowhere" is not good enough for a picture of the walk you took.
     */
    func reassign(from: PhotoOwner, to: PhotoOwner) {
        guard !from.key.isEmpty, !to.key.isEmpty, from.key != to.key else { return }
        var moved = false
        index = index.map { photo in
            guard belongsTo(photo, from) else { return photo }
            moved = true
            return PhotoMeta(id: photo.id, workoutKey: to.key, disciplineId: to.disciplineId, dayKey: to.dayKey,
                             title: to.title, sheet: to.sheet, kind: photo.kind, addedAt: photo.addedAt,
                             bytes: photo.bytes, type: photo.type, width: photo.width, height: photo.height)
        }
        if moved { saveIndex() }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: url(id))
        index.removeAll { $0.id == id }
        saveIndex()
    }

    func removeAll() {
        for photo in index { try? FileManager.default.removeItem(at: url(photo.id)) }
        index = []
        saveIndex()
    }

    /* A name a person can read in a folder six months later — the web app's fileNameFor. */
    static func fileName(_ photo: PhotoMeta, seen: inout Set<String>) -> String {
        var safe = photo.title.folding(options: .diacriticInsensitive, locale: nil)
        safe = safe.replacingOccurrences(of: "[^A-Za-z0-9 +-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        safe = String(safe.prefix(40)).replacingOccurrences(of: " ", with: "-")
        let sport = photo.disciplineId.isEmpty ? "session" : photo.disciplineId
        let ext = photo.type == "image/png" ? "png" : (photo.type == "image/heic" ? "heic" : "jpg")
        var name = [photo.dayKey.isEmpty ? "undated" : photo.dayKey, sport, safe].filter { !$0.isEmpty }.joined(separator: "_") + "." + ext
        let base = String(name.dropLast(ext.count + 1))
        var n = 2
        while seen.contains(name) { name = base + "-\(n)." + ext; n += 1 }
        seen.insert(name)
        return name
    }

    /* Every photo, orphans included, as a stored zip for the share sheet. */
    func exportZip() -> Data {
        var seen = Set<String>()
        var files: [(name: String, data: Data)] = []
        for photo in index {
            guard let data = data(photo.id) else { continue }
            files.append((Self.fileName(photo, seen: &seen), data))
        }
        return ZipBuilder.build(files)
    }

    /*
     * The web app's own export, brought in. Its files are named
     * YYYY-MM-DD_sport_Title.jpg, so each is matched to a session on that day
     * with that sport — by wording first — or to an extra by day. Anything
     * that finds no home is kept as an orphan rather than dropped: it is in
     * the count and in the next export.
     */
    func importZip(_ zip: Data, plan: [Workout], extras: [ExtraSummary]) throws -> (imported: Int, unplaced: Int) {
        let archive = try ZipArchive(data: zip)
        var imported = 0
        var unplaced = 0
        for entry in archive.entries where entry.name.lowercased().hasSuffix(".jpg") || entry.name.lowercased().hasSuffix(".jpeg") || entry.name.lowercased().hasSuffix(".png") {
            guard let data = try? archive.bytes(entry.name), !data.isEmpty else { continue }
            let file = (entry.name as NSString).lastPathComponent
            let stem = (file as NSString).deletingPathExtension
            let parts = stem.components(separatedBy: "_")
            let day = parts.count > 0 ? parts[0] : ""
            let sport = parts.count > 1 ? parts[1] : ""
            let titleWords = parts.count > 2 ? parts[2...].joined(separator: " ").replacingOccurrences(of: "-", with: " ").lowercased() : ""
            let sameDay = plan.filter { $0.dayKey == day && $0.discipline.id == sport }
            let owner: PhotoOwner?
            if let byTitle = sameDay.first(where: { !titleWords.isEmpty && $0.title.lowercased().hasPrefix(String(titleWords.prefix(12))) }) {
                owner = PhotoOwner(byTitle)
            } else if let one = sameDay.first {
                owner = PhotoOwner(one)
            } else if let extra = extras.first(where: { $0.dayKey == day && ($0.activity == sport || sport == "session") }) {
                owner = PhotoOwner(extra: extra)
            } else {
                owner = nil
            }
            if let owner {
                if add(data, to: owner) != nil { imported += 1 }
            } else {
                // Kept with what the name says, shown nowhere, counted everywhere.
                let orphan = PhotoOwner(key: "", disciplineId: sport, dayKey: day, title: titleWords, sheet: "")
                if add(data, to: orphan) != nil { imported += 1; unplaced += 1 }
            }
        }
        return (imported, unplaced)
    }
}

extension PhotoOwner {
    init(key: String, disciplineId: String, dayKey: String, title: String, sheet: String) {
        self.key = key; self.disciplineId = disciplineId; self.dayKey = dayKey; self.title = title; self.sheet = sheet
    }
}
