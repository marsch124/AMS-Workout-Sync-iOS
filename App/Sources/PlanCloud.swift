import Foundation
import UIKit
import CryptoKit
import WorkoutCore

/*
 * The meeting point with iCloud (2.1): the plan, the diary and the Health
 * numbers, in the app's own iCloud folder, so the iPhone, the iPad and the Mac
 * show the same plan. Copied from AMS Workout Companion's CloudSync, which he
 * has used on his iPhone and Mac since 24 November 2026.
 *
 * Each device keeps its own full copy of the plan. The files in iCloud are
 * only where the devices meet: every meeting reads the iCloud file and any
 * conflict copies iCloud parked beside it, joins them with this device's plan
 * (BookMerge — nothing he logged is ever lost) and writes the joined plan to
 * both sides. A file that is missing, still downloading or unreadable is never
 * taken for "empty".
 *
 * Files in `<iCloud folder>/Sync/`:
 *   plan.json                the plan (every device with the plan in the app)
 *   diary.json               morning and how-hard answers (every device)
 *   health-from-iphone.json  Apple Health numbers (the iPhone only)
 *   pause.json               Stop sign and "I'm ill" (every device; 2.3, PauseShare)
 *   devices/<id>.json        one per device (that device only)
 *   plan-original.xlsx       the frozen workbook (written once, never over)
 */
@MainActor
final class PlanCloud: ObservableObject {
    nonisolated static let containerID = "iCloud.com.schabbauer.AMSWorkoutSync"
    static let joinedKey = "sync.joined"
    static let joinedAtKey = "sync.joinedAt"

    /* What a device without a plan of its own sees while it waits (section 2 of the design). */
    enum PlanState: Equatable {
        case unknown
        case off                                     // iCloud signed out or off for the app
        case looking(Int64?)                         // looking / downloading, size when known
        case none                                    // no plan in iCloud yet
        case excel                                   // the iPhone's plan still lives in Excel
        case arrived(sessions: Int, lastChange: Date?, from: String)
        case newer                                   // a plan from a newer app
        case problem(String)
        case member                                  // this device holds the plan and meets iCloud with it
    }

    /* One device's own file: who uses the plan, and when it last met iCloud. */
    struct DeviceFile: Codable, Equatable, Identifiable {
        var id: String
        var kind: String
        var appVersion: String
        var build: String
        var lastMet: Date
        var joinedAt: Date
        var home: String
    }

    @Published private(set) var status: SyncStatus = .off
    @Published private(set) var planState: PlanState = .unknown
    @Published private(set) var devices: [DeviceFile] = []
    @Published private(set) var lastMet: Date?
    /* The newest mark from another device is more than five minutes ahead of this device's clock. */
    @Published private(set) var clockBehind = false
    /* A plan from a second, separate move into the app: he chooses (TwoPlansView). */
    @Published private(set) var otherPlan: PlanBook?
    /* That plan sits beside the iCloud file as a conflict copy (its bytes, to clear it), not in the file itself. */
    private var otherPlanBytes: Data?
    private var otherPlanIsConflict = false
    /* The iCloud file's own book when it is this device's plan (the other plan being a conflict copy). */
    private var cloudMainBook: PlanBook?
    /* Why the plan waits although this device has one (another device's plan has not arrived here yet). */
    @Published private(set) var waitingWhy: String?
    /* "2 things were taken out by your Mac — see Safety copies": said until he has looked. */
    @Published private(set) var takenNotice: String? = UserDefaults.standard.string(forKey: PlanCloud.takenKey)
    static let takenKey = "sync.takenNotice"
    static let sharedKey = "sync.sharedWithOthers"
    /* "Plan from your iPhone · 214 sessions" is shown for two seconds before the app opens. */
    @Published private(set) var showingArrival = false
    /* iCloud already holds a plan: the move-in page offers to use it instead of a second import. */
    @Published private(set) var cloudHasPlan = false
    /* The Health numbers the iPhone shares. */
    @Published private(set) var health: HealthShare?

    /* Another iPad, Mac or iPhone has met iCloud with this plan: going back to Excel would strand it. */
    var otherDevicesUsePlan: Bool { devices.contains { $0.id != Device.id } }

    /* "your Mac", "your iPad", "your iPhone" when one other device uses the plan; else "your other devices". */
    var otherDeviceWords: String {
        let kinds = Set(devices.filter { $0.id != Device.id && $0.home == "app" }.map(\.kind))
        return kinds.count == 1 ? "your " + kinds.first! : "your other devices"
    }

    private unowned let store: Store
    /* `<the app's iCloud folder>/Sync`; nil until iCloud is found (or when it is off). */
    private(set) var root: URL?
    private var fake = false
    private var looking = false
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var running = false
    private var again = false
    private var originalChecked = false
    /* iCloud's list of the folder has arrived (NSMetadataQueryDidFinishGathering): before it, "not there" may only mean "not listed yet". */
    private var gathered = false
    private var gatherWait: Task<Void, Never>?
    private var lastLocalChange: Date?
    private var deviceWrittenAt: Date?
    private var deviceWritten: DeviceFile?
    private var healthSharedAt: Date?

    init(store: Store) {
        self.store = store
        observers.append(NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.accountChanged() }
        })
    }

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    /*
     * Screen tests and pictures run without iCloud, exactly as before 2.1 —
     * unless they hand the app a plain folder to use as iCloud (AMSWS_FAKE_CLOUD).
     */
    private var disabled: Bool {
        #if DEBUG
        if env["AMSWS_FAKE_CLOUD"] != nil { return false }
        if env["AMSWS_FILE"] != nil || env["AMSWS_RESET"] != nil || env["XCTestConfigurationFilePath"] != nil { return true }
        #endif
        return false
    }

    private func set(_ s: SyncStatus) {
        if status != s { status = s }
        if store.syncStatus != s { store.syncStatus = s }
    }

    // MARK: finding iCloud

    /* Finds iCloud (the first time) and meets it. Safe to call often: at launch and whenever the app comes to the front. */
    func start() {
        if disabled {
            set(.off)
            planState = .off
            return
        }
        if root != nil {
            sync()
            return
        }
        guard !looking else { return }
        #if DEBUG
        if let folder = env["AMSWS_FAKE_CLOUD"], !folder.isEmpty {
            fake = true
            found(URL(fileURLWithPath: folder, isDirectory: true))
            return
        }
        #endif
        guard FileManager.default.ubiquityIdentityToken != nil else {
            set(.off)
            planState = .off
            return
        }
        looking = true
        set(.working)
        Task.detached(priority: .utility) {
            // Asking for the folder can take a moment, so not on the main thread.
            let url = FileManager.default.url(forUbiquityContainerIdentifier: PlanCloud.containerID)
            await MainActor.run { self.found(url) }
        }
    }

    private func found(_ container: URL?) {
        looking = false
        guard let container else {
            #if targetEnvironment(simulator)
            // A simulator build carries no iCloud permission: it behaves as before 2.1.
            set(.off)
            planState = .off
            return
            #endif
            // Signed in to iCloud, and still no folder: the app was built without its iCloud permission.
            let why = "This app’s iCloud folder is not available"
            set(.problem(why))
            planState = .problem(why)
            return
        }
        // Before this device's plan meets iCloud for the first time: one copy of everything here, kept for good.
        if !UserDefaults.standard.bool(forKey: Self.joinedKey) {
            guard store.keepBeforeICloud() else {
                let why = "No room for a copy before iCloud, so nothing was shared"
                set(.problem(why))
                planState = .problem(why)
                return
            }
            UserDefaults.standard.set(true, forKey: Self.joinedKey)
            UserDefaults.standard.set(Date(), forKey: Self.joinedAtKey)
        }
        let folder = container.appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("devices", isDirectory: true), withIntermediateDirectories: true)
        #if DEBUG
        seedFakeCloud(folder)
        #endif
        root = folder
        if fake {
            gathered = true
            sync()
        } else {
            // The first meeting waits for iCloud's list of the folder: before it arrives a plan that is
            // there can look absent, and a device with an old plan of its own would set it beside it.
            watch()
            gatherWait?.cancel()
            gatherWait = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled, !self.gathered else { return }
                // Still no list after 20 seconds: it stays "On its way", and nothing is written.
                self.set(.working)
                if case .unknown = self.planState { self.planState = .looking(nil) }
            }
        }
        heartbeat?.cancel()
        let every: UInt64 = fake ? 3 : 30
        heartbeat = Task { [weak self] in
            // A quiet look every half minute while the app is open, in case iCloud's own notice was missed.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: every * 1_000_000_000)
                if UIApplication.shared.applicationState == .active { self?.sync() }
            }
        }
    }

    private func accountChanged() {
        query?.stop()
        query = nil
        heartbeat?.cancel()
        gatherWait?.cancel()
        gathered = false
        root = nil
        originalChecked = false
        start()
    }

    /*
     * A change on this device. The first one after a quiet spell goes up at
     * once (he may close the app straight after logging); several quick
     * changes after it go up together a moment later.
     */
    func localChanged() {
        guard root != nil else { return }
        let now = Date()
        let quiet = lastLocalChange.map { now.timeIntervalSince($0) > 1.5 } ?? true
        lastLocalChange = now
        if quiet { pending?.cancel(); sync() } else { schedule(after: 1.5) }
    }

    /*
     * The app goes to the background: meet iCloud now, with the time iOS
     * allows for it, so what was just logged is on its way before the app sleeps.
     */
    func goingToBackground() {
        guard root != nil, gathered else { return }
        pending?.cancel()
        final class Ticket { var id: UIBackgroundTaskIdentifier = .invalid }
        let ticket = Ticket()
        ticket.id = UIApplication.shared.beginBackgroundTask(withName: "Meet iCloud") {
            UIApplication.shared.endBackgroundTask(ticket.id)
            ticket.id = .invalid
        }
        Task { @MainActor [weak self] in
            if let self {
                // One meeting at a time: wait for one that is under way (at most 20 s), then meet.
                var waited = 0
                while self.running && waited < 200 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
                if !self.running {
                    self.running = true
                    await self.meet()
                    self.running = false
                }
            }
            if ticket.id != .invalid { UIApplication.shared.endBackgroundTask(ticket.id); ticket.id = .invalid }
        }
    }

    /* "Sync now" on the iCloud page. */
    func syncNow() {
        originalChecked = false
        // A list of the folder that never came: ask iCloud for it again.
        if root != nil, !fake, !gathered {
            query?.stop()
            query = nil
            watch()
        }
        healthSharedAt = nil
        start()
    }

    private func schedule(after seconds: Double) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.sync()
        }
    }

    // MARK: watching iCloud's folder

    private func watch() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        q.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            let gathering = name == .NSMetadataQueryDidFinishGathering
            observers.append(NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if gathering { self?.gathered = true; self?.gatherWait?.cancel() }
                    self?.cloudMoved()
                }
            })
        }
        query = q
        q.start()
    }

    /* iCloud says something in the folder is new: fetch what is not here yet, then meet. */
    private func cloudMoved() {
        guard let q = query else { return }
        q.disableUpdates()
        for case let item as NSMetadataItem in q.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
                  status != NSMetadataUbiquitousItemDownloadingStatusCurrent else { continue }
            if url.pathExtension == "json" { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            if url.lastPathComponent == "plan.json", let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber,
               case .looking = planState {
                planState = .looking(size.int64Value)
            }
        }
        q.enableUpdates()
        schedule(after: 0.5)
    }

    // MARK: one meeting

    func sync() {
        guard root != nil else { return }
        // Before iCloud has listed the folder nothing is read or written: it stays "On its way".
        guard gathered else {
            if case .same = status {} else { set(.working) }
            return
        }
        if running {
            again = true
            return
        }
        running = true
        Task { [weak self] in
            await self?.meet()
            guard let self else { return }
            self.running = false
            if self.again {
                self.again = false
                self.schedule(after: 0.3)
            }
        }
    }

    private func meet() async {
        guard let root else { return }
        switch status {
        case .same, .noted, .problem: break
        default: set(.working)
        }
        var settled = true
        var problem: String?

        // Who else uses the plan (and whether an iPhone is still on Excel).
        let devicesFolder = root.appendingPathComponent("devices", isDirectory: true)
        devices = await Task.detached(priority: .utility) { PlanCloud.readDevices(devicesFolder) }.value
        // Once another device has met the plan it is shared for good: a safety copy put back keeps their logs.
        if otherDevicesUsePlan { UserDefaults.standard.set(true, forKey: Self.sharedKey) }
        var took: Int?
        waitingWhy = nil

        // 1. The plan.
        let planURL = root.appendingPathComponent("plan.json")
        let read = await Task.detached(priority: .utility) { CloudFiles.read(planURL) }.value
        cloudHasPlan = read != .absent
        switch store.cloudRole {
        case .busy:
            // Moving in, going back, or a plan here that would not open: iCloud waits.
            settled = false
        case .excel:
            // The plan still lives in Excel on this device: it is not shared. The move-in page offers iCloud's plan.
            break
        case .empty:
            switch await adopt(read) {
            case .waiting: settled = false
            case .problem(let why): problem = why
            case .done: break
            }
        case .member(let book, let version):
            if !showingArrival { planState = .member }
            if read == .waiting {
                settled = false
                break
            }
            let others = devices.filter { $0.id != Device.id }.map(\.home)
            if read == .absent && !PlanMeeting.shouldWriteUp(localHasPlan: true, cloudFileThere: false, otherDevices: others) {
                // Another device's plan lives in the app, and the file has not reached this one yet: wait for it.
                settled = false
                waitingWhy = "Your plan from \(otherDeviceWords) has not reached this \(Device.word) yet. Nothing is sent from here until it has."
                break
            }
            let rank = Device.rank
            let outcome = await Task.detached(priority: .userInitiated) { PlanMeeting.meet(local: book, rank: rank, read: read) }.value
            if let bytes = outcome.unreadable { store.parkFromICloud(bytes, name: "plan.json") }
            if let mark = outcome.newestCloudMark { clockBehind = mark > Date().addingTimeInterval(300) }
            guard let join = outcome.join else {
                settled = false
                break
            }
            switch join.refused {
            case .newerFormat?:
                problem = "Update Triathlon on this device"
            case .differentPlan?:
                otherPlan = outcome.otherPlan ?? outcome.cloudBook
                otherPlanBytes = outcome.otherPlanBytes
                otherPlanIsConflict = outcome.otherPlanIsConflict
                cloudMainBook = outcome.otherPlanIsConflict ? outcome.cloudBook : nil
                problem = "Two different plans — choose one in Settings › iCloud"
            case nil:
                otherPlan = nil
                if join.changesLocal {
                    // The plan here changed while the two were being joined: join again in a moment.
                    guard store.takeFromCloud(join.book, takenAway: join.takenAway, version: version, from: otherDeviceWords) else {
                        settled = false
                        if store.bookVersion != version {
                            again = true
                        } else {
                            // No room, or the plan could not be written: nothing changed here, and nothing goes up.
                            problem = "The plan from your other devices could not be saved on this \(Device.word)"
                        }
                        break
                    }
                    if !join.takenAway.isEmpty { took = join.takenAway.count }
                }
                if !join.changesCloud && join.clearConflicts {
                    // The conflict copies held nothing the file does not: cleared, the file is not written again.
                    let resolving = outcome.mergedConflicts
                    await Task.detached(priority: .utility) { CloudFiles.clear(planURL, resolving: resolving) }.value
                }
                if join.changesCloud {
                    let joined = join.book, resolving = outcome.mergedConflicts
                    let written = await Task.detached(priority: .utility) { () -> Date? in
                        guard let data = try? joined.encoded() else { return nil }
                        return CloudFiles.write(data, to: planURL, resolving: resolving)
                    }.value
                    if written == nil { settled = false }
                }
            }
            if !originalChecked, problem == nil { await original(root) }
        }

        // 2. The diary: every device answers.
        if let why = await diary(root.appendingPathComponent("diary.json")) {
            if why.isEmpty { settled = false } else { problem = problem ?? why }
        }

        // 3. Health: the iPhone writes, the others read.
        await healthShare(root.appendingPathComponent("health-from-iphone.json"))

        // 4. Stop sign and "I'm ill": the same on every device.
        if await pauseShare(root.appendingPathComponent("pause.json")) == false { settled = false }

        // 5. This device's own file.
        await writeDeviceFile(devicesFolder)

        if let took {
            let words = "\(took) thing\(took == 1 ? " was" : "s were") taken out by \(otherDeviceWords) — see Safety copies"
            takenNotice = words
            UserDefaults.standard.set(words, forKey: Self.takenKey)
        }
        if let problem {
            set(.problem(problem))
            if case .member = planState {} else if problem.hasPrefix("Update") { planState = .newer }
        } else if settled {
            let now = Date()
            lastMet = now
            set(takenNotice.map { SyncStatus.noted(now, $0) } ?? .same(now))
        } else {
            set(.working)
        }
    }

    private enum Adopted { case waiting, problem(String), done }

    /* A device with no plan of its own takes the one in iCloud, without asking: there is nothing here to lose. */
    private func adopt(_ read: CloudFiles.Read) async -> Adopted {
        switch read {
        case .absent:
            let excel = devices.contains { $0.home == Store.Home.excel.rawValue && $0.kind == Device.Kind.iPhone.rawValue }
            planState = excel ? .excel : .none
            return .waiting
        case .waiting:
            if case .looking = planState {} else { planState = .looking(nil) }
            return .waiting
        case .found(let data, _, _):
            let result = await Task.detached(priority: .userInitiated) { PlanMeeting.adoptable(read) }.value
            switch result {
            case nil:
                store.parkFromICloud(data, name: "plan.json")
                let why = "The plan in iCloud could not be read. It is kept on this device."
                planState = .problem(why)
                return .problem(why)
            case .failure?:
                planState = .newer
                return .problem("Update Triathlon on this device")
            case .success(let book)?:
                guard store.adoptFromCloud(book) else { return .waiting }
                let from = devices.contains { $0.kind == Device.Kind.iPhone.rawValue && $0.id != Device.id } ? "your iPhone" : "iCloud"
                planState = .arrived(sessions: book.sessions.count, lastChange: book.stamps.values.filter { $0.timeIntervalSince1970 > 1_600_000_000 }.max(), from: from)
                showingArrival = true
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.showingArrival = false
                    self?.planState = .member
                }
                if let root { await original(root) }
                return .done
            }
        }
    }

    /*
     * The iPhone on Excel, on the move-in page: "Use the plan from iCloud".
     * Its waiting entries are written into that plan, never into a second import.
     */
    func useCloudPlanHere() async -> String? {
        guard let root else { return "iCloud is not available on this device just now." }
        let planURL = root.appendingPathComponent("plan.json")
        let read = await Task.detached(priority: .userInitiated) { CloudFiles.read(planURL) }.value
        let result = await Task.detached(priority: .userInitiated) { PlanMeeting.adoptable(read) }.value
        switch result {
        case .success(let book)?:
            guard store.useCloudPlan(book) else { return store.homeProblem ?? "The plan from iCloud could not be saved on this device. Nothing was changed." }
            planState = .member
            await original(root)
            sync()
            return nil
        case .failure?:
            return "The plan in iCloud comes from a newer version of Triathlon. Update the app on this iPhone first."
        case nil:
            return read == .waiting ? "The plan is still on its way from iCloud. Try again in a moment."
                                    : "The plan in iCloud could not be read. Nothing was changed."
        }
    }

    /*
     * He picked one of two plans (TwoPlansView). The one not kept goes into
     * the list of safety copies, so it can be put back from the app.
     */
    func choose(keepThisDevice: Bool) async {
        guard let other = otherPlan, let root, let mine = store.book else { return }
        let planURL = root.appendingPathComponent("plan.json")
        let otherBytes = otherPlanBytes, isConflict = otherPlanIsConflict
        if keepThisDevice {
            store.keepAside(other, as: "other-plan", tail: "icloud")
            if isConflict {
                // The file is this device's plan already: only the other one, beside it, is cleared — else it is offered for ever.
                if let otherBytes { await Task.detached(priority: .userInitiated) { CloudFiles.clear(planURL, resolving: [otherBytes]) }.value }
            } else {
                let written = await Task.detached(priority: .userInitiated) { () -> Date? in
                    guard let data = try? mine.encoded() else { return nil }
                    return CloudFiles.write(data, to: planURL, resolving: [])
                }.value
                if written == nil { set(.problem("The plan could not be put in iCloud just now. Try again.")); return }
            }
        } else {
            // The plan here (with what the iCloud file adds to it, when that is this same plan) is kept aside first.
            let here = cloudMainBook.flatMap { try? BookMerge.merged(mine, $0) } ?? mine
            store.keepAside(here, as: "other-plan", tail: "here")
            guard store.replaceWithCloudPlan(other) else { return }
            if isConflict {
                // The other plan was beside the file: it becomes the file, so the next meeting does not offer the old one back.
                let written = await Task.detached(priority: .userInitiated) { () -> Date? in
                    guard let data = try? other.encoded() else { return nil }
                    return CloudFiles.write(data, to: planURL, resolving: otherBytes.map { [$0] } ?? [])
                }.value
                if written == nil { set(.problem("The plan could not be put in iCloud just now. Try again.")); return }
            }
            originalChecked = false
            await original(root)
        }
        otherPlan = nil
        otherPlanBytes = nil
        otherPlanIsConflict = false
        cloudMainBook = nil
        sync()
    }

    /* He has seen the words about what a meeting took out (the iCloud page or Safety copies). */
    func takenNoticeSeen() {
        guard takenNotice != nil else { return }
        takenNotice = nil
        UserDefaults.standard.removeObject(forKey: Self.takenKey)
        if case .noted(let at, _) = status { set(.same(at)) }
    }

    /* Going back to Excel on the only device: the plan in iCloud is put aside (kept), so nothing adopts it later. */
    func planLeftTheApp() async {
        guard let root else { return }
        let planURL = root.appendingPathComponent("plan.json")
        let aside = root.appendingPathComponent("plan-left-\(Int(Date().timeIntervalSince1970)).json")
        _ = await Task.detached(priority: .utility) { CloudFiles.moveAside(planURL, to: aside) }.value
        // OPEN: a device that adopted the plan and then sees it gone keeps its own copy and puts it back up on
        // its next meeting. That is why going back is closed once another device has joined (plan-go-back-closed).
    }

    // MARK: the diary

    /* Nil when done; "" when it must wait; words for a problem. */
    private func diary(_ url: URL) async -> String? {
        let read = await Task.detached(priority: .utility) { CloudFiles.read(url) }.value
        var cloud: [DiaryDoc] = []
        var there = false
        var merged: [Data] = []
        switch read {
        case .waiting: return ""
        case .absent: break
        case .found(let data, let conflicts, _):
            if let doc = try? DiaryDoc.decoded(data) { cloud.append(doc); there = true } else { store.parkFromICloud(data, name: "diary.json") }
            for bytes in conflicts {
                if let doc = try? DiaryDoc.decoded(bytes) { cloud.append(doc); merged.append(bytes) }
            }
        }
        let join = DiaryDoc.join(local: Diary.shared.doc, cloud: cloud, cloudFileThere: there)
        if join.newerApp { return "Update Triathlon on this device" }
        if join.changesLocal { Diary.shared.takeFromCloud(join.doc) }
        if join.changesCloud {
            let doc = join.doc
            let written = await Task.detached(priority: .utility) { () -> Date? in
                guard let data = try? doc.encoded() else { return nil }
                return CloudFiles.write(data, to: url, resolving: merged)
            }.value
            if written == nil { return "" }
        }
        return nil
    }

    // MARK: Stop sign and "I'm ill", on every device

    /*
     * A separate small file beside the plan, never part of the plan or its
     * merge. Every device reads it, joins it with its own taps by
     * PauseShare.join (newest wins, but a pause is never lifted by an older
     * all clear, nor by one that never saw it) and writes back what is joined.
     * False when it must wait; nothing is read or written while the
     * suggestions' own notes on this device cannot be read.
     */
    private func pauseShare(_ url: URL) async -> Bool {
        let keeper = SuggestionKeeper.shared
        guard let local = keeper.sharedPause else { return true }
        let read = await Task.detached(priority: .utility) { CloudFiles.read(url) }.value
        var cloud: [PauseShare] = []
        var mainThere = false
        var merged: [Data] = []
        switch read {
        case .waiting: return false
        case .absent: break
        case .found(let data, let conflicts, _):
            if let share = try? PauseShare.decoded(data) {
                cloud.append(share)
                mainThere = true
            } else {
                store.parkFromICloud(data, name: "pause.json")
            }
            for bytes in conflicts {
                if let share = try? PauseShare.decoded(bytes) { cloud.append(share); merged.append(bytes) }
            }
        }
        var joined = PauseShare.join(local: local, cloud: cloud)
        if joined != local, let kept = keeper.pauseFromICloud(joined) { joined = kept }
        guard !mainThere || cloud.first != joined || !merged.isEmpty else { return true }
        let share = joined
        let written = await Task.detached(priority: .utility) { () -> Date? in
            guard let data = try? share.encoded() else { return nil }
            return CloudFiles.write(data, to: url, resolving: merged)
        }.value
        return written != nil
    }

    // MARK: Apple Health, from the iPhone

    private func healthShare(_ url: URL) async {
        let read = await Task.detached(priority: .utility) { CloudFiles.read(url) }.value
        var all: [HealthShare] = []
        var conflictBytes: [Data] = []
        if case .found(let data, let conflicts, _) = read {
            if let share = try? HealthShare.decoded(data) { all.append(share) }
            for bytes in conflicts {
                if let share = try? HealthShare.decoded(bytes) { all.append(share) }
                conflictBytes.append(bytes)
            }
        }
        let newest = HealthShare.newest(all)
        if Device.isPhone {
            // Asked of Health at most every twenty minutes; the numbers change once a morning.
            if let at = healthSharedAt, Date().timeIntervalSince(at) < 20 * 60, conflictBytes.isEmpty { return }
            guard let share = await HealthImport.shared.shareForOtherDevices(previous: newest, today: store.today) else { return }
            if share == newest && conflictBytes.isEmpty { healthSharedAt = Date(); return }
            let written = await Task.detached(priority: .utility) { () -> Date? in
                guard let data = try? share.encoded() else { return nil }
                return CloudFiles.write(data, to: url, resolving: conflictBytes)
            }.value
            if written != nil { healthSharedAt = Date(); health = share }
        } else if let newest, newest != health {
            health = newest
            HealthImport.shared.shared = newest
            Diary.shared.foundFromIPhone(newest.found)
        }
    }

    // MARK: who uses the plan

    nonisolated static func readDevices(_ folder: URL) -> [DeviceFile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var out: [DeviceFile] = []
        for name in CloudFiles.names(in: folder) where name.hasSuffix(".json") {
            if case .found(let data, _, _) = CloudFiles.read(folder.appendingPathComponent(name)),
               let file = try? decoder.decode(DeviceFile.self, from: data) {
                out.append(file)
            }
        }
        return out
    }

    /* Written when something in it changed, and otherwise at most every ten minutes — not at every meeting. */
    private func writeDeviceFile(_ folder: URL) async {
        let info = Bundle.main.infoDictionary
        let mine = DeviceFile(id: Device.id, kind: Device.kind.rawValue,
                              appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                              build: info?["CFBundleVersion"] as? String ?? "?",
                              lastMet: Date(),
                              joinedAt: UserDefaults.standard.object(forKey: Self.joinedAtKey) as? Date ?? Date(),
                              home: store.home == .app ? "app" : (store.hasNoPlanAtAll ? "none" : "excel"))
        if let was = deviceWritten, let at = deviceWrittenAt, Date().timeIntervalSince(at) < 600,
           was.home == mine.home, was.appVersion == mine.appVersion, was.build == mine.build { return }
        let url = folder.appendingPathComponent(Device.id + ".json")
        let written = await Task.detached(priority: .utility) { () -> Date? in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(mine) else { return nil }
            return CloudFiles.write(data, to: url)
        }.value
        if written != nil {
            deviceWritten = mine
            deviceWrittenAt = Date()
            if let i = devices.firstIndex(where: { $0.id == mine.id }) { devices[i] = mine } else { devices.append(mine) }
        }
    }

    // MARK: the frozen workbook

    nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /*
     * Up once from the device that has it; down to a device that lacks it, so
     * "Save a copy now" works on the iPad and the Mac. Never overwritten: a
     * different workbook already there goes beside it under its own name, and
     * the plan's own mark (origin.originalHash) says which one is right.
     */
    private func original(_ root: URL) async {
        guard let book = store.book else { return }
        let local = store.originalFileURL
        let wanted = book.origin.originalHash
        let takenMs = Int64((book.origin.takenAt.timeIntervalSince1970 * 1000).rounded())
        let arrived: Data? = await Task.detached(priority: .utility) { () -> Data? in
            let fm = FileManager.default
            let main = root.appendingPathComponent("plan-original.xlsx")
            if let mine = try? Data(contentsOf: local) {
                if CloudFiles.writeOnce(mine, to: main) { return nil }
                if case .found(let there, _, _) = CloudFiles.read(main), PlanCloud.hash(there) != PlanCloud.hash(mine) {
                    _ = CloudFiles.writeOnce(mine, to: root.appendingPathComponent("plan-original-\(takenMs).xlsx"))
                }
                return nil
            }
            guard !fm.fileExists(atPath: local.path) else { return nil }
            for name in CloudFiles.names(in: root) where name.hasPrefix("plan-original") && name.hasSuffix(".xlsx") {
                guard case .found(let data, _, _) = CloudFiles.read(root.appendingPathComponent(name)) else { continue }
                if let wanted, PlanCloud.hash(data) != wanted { continue }
                if wanted == nil, name != "plan-original.xlsx" { continue }
                return data
            }
            return nil
        }.value
        if let arrived { store.saveOriginal(arrived) }
        originalChecked = store.hasOriginal
    }

    #if DEBUG
    /* AMSWS_CLOUD_SEED=<workbook>: the fake iCloud folder starts with that plan in it, as if an iPhone had put it there. */
    private func seedFakeCloud(_ folder: URL) {
        guard fake, let path = env["AMSWS_CLOUD_SEED"],
              !FileManager.default.fileExists(atPath: folder.appendingPathComponent("plan.json").path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let taken = try? PlanImport.read(data, fileName: URL(fileURLWithPath: path).lastPathComponent, today: store.today),
              let bytes = try? taken.book.encoded() else { return }
        try? bytes.write(to: folder.appendingPathComponent("plan.json"), options: .atomic)
        let phone = DeviceFile(id: "seed-iphone", kind: Device.Kind.iPhone.rawValue, appVersion: "2.1", build: "0",
                               lastMet: Date(), joinedAt: Date(), home: Store.Home.app.rawValue)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try? encoder.encode(phone).write(to: folder.appendingPathComponent("devices/seed-iphone.json"), options: .atomic)
    }
    #endif
}
