import Foundation

/*
 * The disk side of meeting iCloud, kept here (not in the app) so a test on
 * the Mac can drive two devices' worth of books through a plain folder.
 *
 * The rules that keep his plan safe live in these few lines:
 *   - a file that is not there is "absent", one that is there but not yet on
 *     this device is "waiting" — neither is ever read as "empty";
 *   - every conflict copy iCloud parked beside the file is read and joined;
 *   - after writing, only the conflict copies that were joined are cleared,
 *     so one that arrived in the meantime waits for the next meeting.
 * Every call here blocks (file coordination): never call it on the main thread.
 */
public enum CloudFiles {
    public enum Read: Equatable {
        /* Not in the folder, as far as this device knows. */
        case absent
        /* There, but not on this device yet; the download has been asked for. */
        case waiting
        /* The file, the conflict copies iCloud parked beside it, and the file's date. */
        case found(Data, conflicts: [Data], modified: Date)
    }

    public static func read(_ url: URL) -> Read {
        let fm = FileManager.default
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        if !fm.fileExists(atPath: url.path) {
            guard fm.fileExists(atPath: placeholder.path) else { return .absent }
            try? fm.startDownloadingUbiquitousItem(at: url)
            return .waiting
        }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .contentModificationDateKey])
        if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? fm.startDownloadingUbiquitousItem(at: url)
            return .waiting
        }
        // A newer version is in iCloud than the one here: ask for it; this meeting works with what is here.
        if values?.ubiquitousItemDownloadingStatus == .downloaded { try? fm.startDownloadingUbiquitousItem(at: url) }
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { at in
            data = try? Data(contentsOf: at)
        }
        // Could not be read just now (still being written, or coordination failed): wait, never "empty".
        guard let data, !data.isEmpty else { return .waiting }
        var conflicts: [Data] = []
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            if let bytes = try? Data(contentsOf: version.url) { conflicts.append(bytes) }
        }
        return .found(data, conflicts: conflicts, modified: values?.contentModificationDate ?? Date())
    }

    /* Writes the file and clears the conflict copies that were joined into it — only those. Returns the file's new date. */
    @discardableResult
    public static func write(_ data: Data, to url: URL, resolving merged: [Data] = []) -> Date? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { at in
            ok = (try? data.write(to: at, options: .atomic)) != nil
        }
        guard ok else { return nil }
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            guard let bytes = try? Data(contentsOf: version.url), merged.contains(bytes) else { continue }
            version.isResolved = true
            try? version.remove()
        }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }

    /* Clears the conflict copies that went into a join, without writing the file (it already holds them). */
    public static func clear(_ url: URL, resolving merged: [Data]) {
        guard !merged.isEmpty else { return }
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            guard let bytes = try? Data(contentsOf: version.url), merged.contains(bytes) else { continue }
            version.isResolved = true
            try? version.remove()
        }
    }

    /* Writes a file only if nothing is there yet (or on its way): the frozen workbook is never overwritten. */
    public static func writeOnce(_ data: Data, to url: URL) -> Bool {
        if read(url) != .absent { return false }
        return write(data, to: url) != nil
    }

    /* Moves a file aside inside the folder (coordinated), keeping it. */
    @discardableResult
    public static func moveAside(_ url: URL, to other: URL) -> Bool {
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMoving, writingItemAt: other, options: .forReplacing, error: &error) { from, to in
            ok = (try? FileManager.default.moveItem(at: from, to: to)) != nil
        }
        return ok
    }

    /* The names in a folder, with "not yet downloaded" placeholders given their real names. */
    public static func names(in folder: URL) -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Array(Set(all.map { n in
            n.hasPrefix(".") && n.hasSuffix(".icloud") ? String(n.dropFirst().dropLast(7)) : n
        }.filter { !$0.hasPrefix(".") })).sorted()
    }

    /* The "format" number written in a JSON file, read without decoding anything else. */
    public static func formatNumber(_ data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["format"] as? Int
    }
}

/*
 * One meeting of this device's plan book with the iCloud file, worked out
 * without touching the disk or the screen. The app reads (CloudFiles.read),
 * calls this off the main thread, puts the result in place on the main
 * thread and writes (CloudFiles.write).
 */
public enum PlanMeeting {
    public struct Outcome: Equatable {
        /* Nil while the iCloud file is still on its way: nothing is done this time. */
        public var join: BookJoin?
        /* The iCloud file's bytes when they could not be read as a plan: kept on this device before anything is written over them. */
        public var unreadable: Data?
        /* The conflict copies that went into the join — the only ones the write may clear. */
        public var mergedConflicts: [Data] = []
        /* The book in the iCloud file, as it was read. */
        public var cloudBook: PlanBook?
        /* The newest mark among the books from iCloud, to notice a clock that is behind. */
        public var newestCloudMark: Date?
        /* Two different plans: the one in iCloud that really differs from this device's (the file or a conflict copy). */
        public var otherPlan: PlanBook?
        /* Its bytes, so a conflict copy can be cleared once he has chosen. */
        public var otherPlanBytes: Data?
        /* The other plan is a conflict copy beside the file, not the file itself. */
        public var otherPlanIsConflict = false
    }

    /*
     * A device that still shows a workbook (the plan in Excel) while iCloud holds
     * the plan from the app. The iPhone is asked, on its move-in page: its Excel
     * plan may be the one he works in. An iPad or Mac never held the plan itself:
     * a link to the workbook from before 2.2 only SHOWS the old Excel file, which
     * nobody writes any more. So there iCloud's plan is taken without asking
     * (2.4.1; the Mac had gone on showing the old file and offering Dropbox).
     */
    public static func takesCloudPlanOverWorkbook(isPhone: Bool, cloudHasPlan: Bool) -> Bool {
        !isPhone && cloudHasPlan
    }

    /*
     * May a device that holds a plan put it into iCloud? Always when the file is
     * there (it is joined first). When the file is not there, only if no other
     * device says its plan lives in the app: else the file is most likely still
     * on its way to this device, and writing now would set an old plan beside it.
     * `otherDevices` are the other devices' homes ("app", "excel", "none").
     */
    public static func shouldWriteUp(localHasPlan: Bool, cloudFileThere: Bool, otherDevices: [String]) -> Bool {
        guard localHasPlan else { return false }
        if cloudFileThere { return true }
        return !otherDevices.contains("app")
    }

    public static func meet(local: PlanBook, rank: Int, read: CloudFiles.Read) -> Outcome {
        var out = Outcome()
        var cloud: [PlanBook] = []
        var fileThere = false
        switch read {
        case .waiting:
            return out
        case .absent:
            break
        case .found(let data, let conflicts, _):
            if let format = CloudFiles.formatNumber(data), format > PlanBook.currentFormat {
                // A newer app wrote it: refused, whether or not this app could half-read it.
                out.join = BookJoin(book: local, changesLocal: false, changesCloud: false,
                                    refused: .newerFormat(format), takenAway: [])
                return out
            }
            if let book = try? PlanBook.decoded(data) {
                cloud.append(book)
                out.cloudBook = book
                fileThere = true
            } else {
                out.unreadable = data
            }
            for bytes in conflicts {
                if let format = CloudFiles.formatNumber(bytes), format > PlanBook.currentFormat {
                    out.join = BookJoin(book: local, changesLocal: false, changesCloud: false,
                                        refused: .newerFormat(format), takenAway: [])
                    return out
                }
                if let book = try? PlanBook.decoded(bytes) {
                    cloud.append(book)
                    out.mergedConflicts.append(bytes)
                }
            }
        }
        out.newestCloudMark = cloud.flatMap { Array($0.stamps.values) }.max()
        out.join = BookMerge.join(local: local.baselined(rank: rank), cloud: cloud, cloudFileThere: fileThere)
        if case .differentPlan? = out.join?.refused, let i = cloud.firstIndex(where: { !BookMerge.samePlan($0, local) }) {
            // The book that really differs from this device's: the file, or one of the conflict copies.
            out.otherPlan = cloud[i]
            out.otherPlanIsConflict = !(fileThere && i == 0)
            if out.otherPlanIsConflict, case .found(_, let conflicts, _) = read {
                out.otherPlanBytes = conflicts.first { (try? PlanBook.decoded($0)) == cloud[i] }
            }
        }
        return out
    }

    /* The book a device with no plan of its own takes from iCloud; nil while it is not there yet or cannot be used. */
    public static func adoptable(_ read: CloudFiles.Read) -> Result<PlanBook, BookMerge.Refusal>? {
        guard case .found(let data, let conflicts, _) = read else { return nil }
        let all = [data] + conflicts
        if let newest = all.compactMap(CloudFiles.formatNumber).max(), newest > PlanBook.currentFormat {
            return .failure(.newerFormat(newest))
        }
        let books = all.compactMap { try? PlanBook.decoded($0) }
        guard !books.isEmpty else { return nil }
        do { return .success(try BookMerge.merged(books)) } catch let r as BookMerge.Refusal {
            // The file and a conflict copy from two different imports: the file's own book, the copy waits for him.
            if case .differentPlan = r { return .success(books[0]) }
            return .failure(r)
        } catch { return nil }
    }
}
