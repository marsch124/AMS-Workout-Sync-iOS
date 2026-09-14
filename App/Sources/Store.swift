import Foundation
import SwiftUI
import WorkoutCore

/*
 * Where the plan comes from, and the copy kept on the phone.
 *
 * Stage 1 opens the workbook through the Files app — Dropbox's own provider —
 * rather than signing in to Dropbox. That means no login to set up, and the
 * app holds permission for the one file he picked and nothing else. It also
 * means it cannot write even by accident: nothing here ever opens the file for
 * writing.
 *
 * The file is remembered as a bookmark and read again whenever the app comes
 * to the front. What was last read successfully is kept in Application
 * Support, so the plan still opens on a plane.
 */
@MainActor
final class Store: ObservableObject {
    enum Phase: Equatable { case empty, loading, ready, failed(String) }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var plan: [Workout] = []
    @Published private(set) var mapping: Mapping?
    @Published private(set) var fileName: String = ""
    @Published private(set) var readAt: Date?
    @Published private(set) var fromCache = false
    @Published private(set) var lastProblem: String?

    private let bookmarkKey = "workbookBookmark"
    private let nameKey = "workbookName"
    private let readAtKey = "workbookReadAt"

    /* The "today" everything is measured from. Fixed by a launch argument in
       DEBUG so a screenshot of a given day can be taken on any day. */
    let todayOverride: String? = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AMSWS_TODAY"]
        #else
        return nil
        #endif
    }()

    var today: String { todayOverride ?? PlanView.todayKey() }

    var view: PlanView? { mapping.map { PlanView(plan: plan, mapping: $0) } }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workbook.xlsx")
    }

    init() {
        fileName = UserDefaults.standard.string(forKey: nameKey) ?? ""
        readAt = UserDefaults.standard.object(forKey: readAtKey) as? Date
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AMSWS_FILE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            fileName = URL(fileURLWithPath: path).lastPathComponent
            parse(data, cached: false)
            return
        }
        #endif
        if let data = try? Data(contentsOf: cacheURL) {
            parse(data, cached: true)
        }
    }

    var hasWorkbook: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil || !plan.isEmpty }

    /* The file picked in the Files app. */
    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
            fileName = url.lastPathComponent
        } catch {
            lastProblem = "The app could not remember that file: \(error.localizedDescription)"
        }
        refresh()
    }

    /* Read the workbook again from wherever it lives. */
    func refresh() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_FILE"] != nil { return }
        #endif
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        if plan.isEmpty { phase = .loading }

        Task.detached(priority: .userInitiated) { [bookmarkKey] in
            var stale = false
            let result: Result<Data, Error>
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
                // Coordinated, so the Dropbox provider hands over its current
                // copy rather than whatever it last downloaded.
                var coordinationError: NSError?
                var read: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { real in
                    read = Result { try Data(contentsOf: real) }
                }
                if let coordinationError { throw coordinationError }
                result = read
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                switch result {
                case .success(let data):
                    self.parse(data, cached: false)
                case .failure(let error):
                    self.lastProblem = "Could not read the workbook just now: \(error.localizedDescription)"
                    if self.plan.isEmpty { self.phase = .failed(self.lastProblem!) }
                }
            }
        }
    }

    private func parse(_ data: Data, cached: Bool) {
        do {
            let workbook = try Workbook(data: data)
            guard let mapping = try Plan.mapping(for: workbook) else {
                throw NSError(domain: "AMSWorkoutSync", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Nothing in this workbook looks like a training plan."])
            }
            self.plan = Plan.build(workbook, mapping)
            self.mapping = mapping
            self.fromCache = cached
            self.phase = .ready
            if !cached {
                lastProblem = nil
                readAt = Date()
                UserDefaults.standard.set(readAt, forKey: readAtKey)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            lastProblem = error.localizedDescription
            if plan.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    func workout(_ key: String) -> Workout? { plan.first { $0.key == key } }
}
