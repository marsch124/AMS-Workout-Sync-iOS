import SwiftUI
import UniformTypeIdentifiers
import WorkoutCore

/*
 * 2.9 lane "gym": the Gym sessions card on the Body page. The machines, sets and weights are logged in
 * AMS Workout Companion, which writes them into AMS Garmin/Workout Companion sessions.json in iCloud
 * Drive (the Garmin Board reads the same file). The app may not read another folder unless he picks it,
 * so he chooses the "AMS Garmin" folder once (Settings › Garmin, or the card); the choice is kept on this
 * device as a security-scoped bookmark. The app only reads the file; it never writes it.
 */
@MainActor
final class GymReader: ObservableObject {
    static let shared = GymReader()

    enum State { case noFolder, noFile, ready }

    @Published private(set) var state: State = .noFolder
    @Published private(set) var sessions: [GymSession] = []
    @Published private(set) var folderName: String?
    @Published private(set) var reading = false

    private var lastRead: Date?
    private var lastToday = ""
    private static let key = "gym.folder.bookmark.v1"

    private static var fake: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_FAKE_GARMIN"] != nil
        #else
        return false
        #endif
    }
    private static var fakeNoFolder: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_GYM_NO_FOLDER"] != nil
        #else
        return false
        #endif
    }

    var hasFolder: Bool { Self.fake ? !Self.fakeNoFolder : UserDefaults.standard.data(forKey: Self.key) != nil }
    var newest: GymSession? { sessions.first }

    /* The page appeared: read when the last read is older than five minutes (the file is local). */
    func readIfDue(today: String) async {
        if let lastRead, Date().timeIntervalSince(lastRead) < 300, lastToday == today { return }
        await read(today: today)
    }

    func read(today: String) async {
        lastToday = today
        if Self.fake {
            if Self.fakeNoFolder { state = .noFolder; sessions = []; folderName = nil } else {
                sessions = Self.invented(today: today); state = .ready; folderName = "AMS Garmin"
            }
            lastRead = Date()
            return
        }
        guard let data = UserDefaults.standard.data(forKey: Self.key) else {
            state = .noFolder; sessions = []; folderName = nil; return
        }
        reading = true
        defer { reading = false }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            state = .noFolder; sessions = []; folderName = nil; return
        }
        folderName = folder.lastPathComponent
        let bytes = await Task.detached { Self.readFile(in: folder) }.value
        if stale, let fresh = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.key)
        }
        lastRead = Date()
        guard let bytes else { state = .noFile; sessions = []; return }
        sessions = GymSessions.parse(bytes)
        state = sessions.isEmpty ? .noFile : .ready
    }

    /* The folder he picked: keep a bookmark to it on this device and read at once. */
    func choose(_ result: Result<URL, Error>, today: String) async {
        guard case .success(let url) = result else { return }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        await read(today: today)
    }

    /* Reads the file with a file coordinator, so an iCloud file that is not yet on this device is fetched first. Never writes. */
    nonisolated private static func readFile(in folder: URL) -> Data? {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(GymSessions.fileName)
        var result: Data?
        var failure: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: file, options: [], error: &failure) { url in
            result = try? Data(contentsOf: url)
        }
        return failure == nil ? result : nil
    }

    /* Invented sample sessions for the picture switch (AMSWS_FAKE_GARMIN); the days follow today. */
    private static func invented(today: String) -> [GymSession] {
        func day(_ n: Int) -> String { PlanView.addDays(today, -n) }
        let curl = GymEntry(name: "Leg press", muscle: "Legs", sets: "80 × 12, 90 × 10, 90 × 8 kg", setCount: 3, topKg: 90)
        let press = GymEntry(name: "Chest press", muscle: "Chest", sets: "40 kg × 12, 10", setCount: 2, topKg: 40)
        let row = GymEntry(name: "Seated row", muscle: "Back", sets: "35 × 12, 37,5 × 10 kg", setCount: 2, topKg: 37.5)
        let bike = GymEntry(name: "Exercise bike", sets: "15 min · level 6", setCount: 1)
        return [
            GymSession(id: "g1", date: day(2), minutes: 64, gym: "City Gym", feel: "good", machines: 4, sets: 11, liftedKg: 4_320, bests: ["Leg press"], entries: [curl, press, row, bike]),
            GymSession(id: "g2", date: day(5), minutes: 81, gym: "City Gym", feel: "ok", machines: 3, sets: 9, liftedKg: 3_680, entries: [curl, press, row]),
            GymSession(id: "g3", date: day(9), minutes: 62, gym: "City Gym", feel: "great", machines: 3, sets: 9, liftedKg: 2_950, entries: [press, row, bike]),
            GymSession(id: "g4", date: day(13), minutes: 55, gym: "City Gym", machines: 2, sets: 6, liftedKg: 1_980, entries: [curl, press]),
        ]
    }
}

/* One shared folder picker: the card and Settings both open it. */
private struct GymFolderImporter: ViewModifier {
    @Binding var isPresented: Bool
    let today: String
    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            Task { await GymReader.shared.choose(result, today: today) }
        }
    }
}

private extension View {
    func gymFolderImporter(_ on: Binding<Bool>, today: String) -> some View { modifier(GymFolderImporter(isPresented: on, today: today)) }
}

/* The machine's line split in its name and what follows it ("best 90 kg × 10"). */
private func machineParts(_ e: GymEntry) -> (String, String) {
    let line = GymSessions.machineLine(e)
    return (e.name, String(line.dropFirst(e.name.count)))
}

struct GymCard: View {
    let day: String
    @ObservedObject private var reader = GymReader.shared
    @State private var picked: String?
    @State private var choosing = false

    private var shown: GymSession? {
        reader.sessions.first { $0.id == picked } ?? reader.sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("GYM SESSIONS")
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body)
            if reader.state == .ready, let s = shown {
                filled(s)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
        .gymFolderImporter($choosing, today: day)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-gym-card")
    }

    @ViewBuilder private var empty: some View {
        Text(reader.state == .noFile
             ? "No gym sessions found in that folder yet. They appear once AMS Workout Companion has saved one to AMS Garmin."
             : "Choose the AMS Garmin folder once in Settings › Garmin to see your gym sessions here.")
            .font(.caption).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("body-gym-empty")
        Button("Choose folder") { choosing = true }
            .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini).tint(Theme.body)
            .padding(.top, 5)
            .accessibilityIdentifier("body-gym-choose")
    }

    @ViewBuilder private func filled(_ s: GymSession) -> some View {
        let latest = reader.sessions.first
        let isLatest = s.id == latest?.id
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(BodyPage.grouped(s.liftedKg ?? 0)).font(.title2.weight(.bold))
            Text("kg").font(.footnote.weight(.semibold))
        }
        .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityIdentifier("body-gym-kg")
        Text(GymSessions.headLine(s)).font(.caption).foregroundStyle(Theme.secondary)
            .accessibilityIdentifier("body-gym-head")
        Text(GymSessions.countsLine(s, today: isLatest ? day : nil)).font(.caption).foregroundStyle(Theme.secondary)
            .accessibilityIdentifier("body-gym-counts")
        if isLatest, let l = latest, let c = GymSessions.compareLine(l, reader.sessions.dropFirst().first) {
            Text(c).font(.caption).foregroundStyle(Theme.secondary)
                .accessibilityIdentifier("body-gym-compare")
        }
        if !isLatest {
            Button("Back to the latest") { picked = nil }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini).tint(Theme.body)
                .padding(.top, 4)
                .accessibilityIdentifier("body-gym-back")
        }
        VStack(alignment: .leading, spacing: 3) {
            if s.entries.isEmpty {
                Text("No machines saved for this session").font(.caption).foregroundStyle(Theme.secondary)
            }
            ForEach(Array(s.entries.enumerated()), id: \.offset) { i, e in
                let p = machineParts(e)
                (Text(p.0).font(.footnote.weight(.semibold)).foregroundColor(Theme.text)
                 + Text(p.1 + (s.bests.contains(e.name) ? " · new best" : "") + (e.pain ? " · pain noted" : ""))
                    .font(.footnote).foregroundColor(Theme.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-gym-machine-\(i)")
            }
        }
        .padding(.top, 6)
        recent(selected: s.id)
        Text("Tap a session to see it here.").font(.caption2).foregroundStyle(Theme.secondary).padding(.top, 4)
    }

    @ViewBuilder private func recent(selected: String) -> some View {
        let list = Array(reader.sessions.prefix(6))
        let top = max(list.compactMap(\.liftedKg).max() ?? 1, 1)
        VStack(spacing: 2) {
            ForEach(list) { r in
                Button { picked = (r.id == reader.sessions.first?.id) ? nil : r.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(GymSessions.dayText(r.date)).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                            Text([r.gym, r.minutes.map { formatDuration($0 * 60) }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                            if let kg = r.liftedKg, kg > 0 {
                                Text(BodyPage.grouped(kg) + " kg").font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                            }
                            Spacer(minLength: 0)
                        }
                        GeometryReader { g in
                            Capsule().fill(Theme.body.opacity(0.55))
                                .frame(width: max(3, g.size.width * CGFloat((r.liftedKg ?? 0) / top)), height: 3)
                        }.frame(height: 3)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(r.id == selected ? Theme.body.opacity(0.14) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(GymSessions.headLine(r)), \(BodyPage.grouped(r.liftedKg ?? 0)) kilograms. Shows this session in the card.")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("body-gym-row-\(r.id)")
            }
        }
    }
}

/* Settings › Garmin: where he chooses the AMS Garmin folder once. */
struct GymFolderSection: View {
    let today: String
    @ObservedObject private var reader = GymReader.shared
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gym sessions").font(.headline).foregroundStyle(Theme.settings)
            Text("From AMS Workout Companion, as on your Garmin Board.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            if reader.hasFolder {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reader.folderName ?? "AMS Garmin").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                            .accessibilityIdentifier("garmin-gym-folder")
                        Text(reader.newest.map { "Newest session: " + GymSessions.dayText($0.date) } ?? "No session found in it yet")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                            .accessibilityIdentifier("garmin-gym-newest")
                    }
                    Spacer(minLength: 0)
                    Button("Change") { choosing = true }
                        .settingsButton(tint: Theme.settings)
                        .accessibilityIdentifier("garmin-gym-change")
                }
            } else {
                Button { choosing = true } label: {
                    Text("Choose the AMS Garmin folder").font(.body.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.settings))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("garmin-gym-choose")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .gymFolderImporter($choosing, today: today)
        .task { await reader.readIfDue(today: today) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garmin-gym-section")
    }
}

/* On a strength session's page: that day's gym machines, sets and best weights (nothing when the file has no session that day). */
struct GymDayBlock: View {
    let day: String
    let today: String
    @ObservedObject private var reader = GymReader.shared

    var body: some View {
        let list = reader.state == .ready ? GymSessions.onDay(reader.sessions, day) : []
        Group {
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(list) { s in
                        Text("GYM").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Theme.body)
                        Text([GymSessions.headLine(s).components(separatedBy: " · ").dropFirst().joined(separator: " · "),
                              GymSessions.countsLine(s, today: nil),
                              (s.liftedKg ?? 0) > 0 ? BodyPage.grouped(s.liftedKg ?? 0) + " kg" : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.secondary)
                        ForEach(Array(s.entries.enumerated()), id: \.offset) { _, e in
                            let p = machineParts(e)
                            (Text(p.0).font(.footnote.weight(.semibold)).foregroundColor(Theme.text)
                             + Text(p.1).font(.footnote).foregroundColor(Theme.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bodyTile))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("body-gym-session-block")
            }
        }
        .task { await reader.readIfDue(today: today) }
    }
}
