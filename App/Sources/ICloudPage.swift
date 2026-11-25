import SwiftUI
import WorkoutCore

/*
 * Settings → iCloud: whether the plan is the same on all his devices, which
 * devices use it and when each last met iCloud, a way to meet now, and the
 * copy of the plan from before iCloud. The dot always has its words beside it.
 *
 * DEBUG: AMSWS_CLOUD_PAGE=1 opens this page from Settings.
 */
struct ICloudPage: View {
    @EnvironmentObject var store: Store
    @State private var beforeCopy: URL?

    var body: some View {
        let cloud = store.cloud
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StatusDot(status: cloud.status)
                    Text(cloud.status.words).font(.headline).foregroundStyle(Theme.text)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("icloud-status")
                Text(detail(cloud)).font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("icloud-detail")
                if let taken = cloud.takenNotice {
                    Text(taken).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("icloud-taken")
                }
                if cloud.clockBehind {
                    Text("This \(Device.word)’s clock is behind. Set it to the right time (Settings → General → Date & Time → Set Automatically), so the newest change always wins.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("icloud-clock-behind")
                }

                if cloud.otherPlan != nil, let mine = store.book, let theirs = cloud.otherPlan {
                    TwoPlansView(mine: mine, theirs: theirs, theirsFrom: cloud.otherDeviceWords) { keepMine in
                        Task { await cloud.choose(keepThisDevice: keepMine) }
                    }
                }

                Button { cloud.syncNow() } label: {
                    Text("Sync now").font(.headline).frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent).tint(Theme.today)   // the main button is never grey
                .accessibilityIdentifier("icloud-sync-now")

                SectionHeading(text: "Your devices")
                VStack(alignment: .leading, spacing: 0) {
                    let list = devices(cloud)
                    if list.isEmpty {
                        Text("None yet. Each iPhone, iPad and Mac appears here once it has met iCloud.")
                            .font(.footnote).foregroundStyle(Theme.secondary).padding(.vertical, 8)
                    }
                    ForEach(list) { d in
                        HStack(spacing: 6) {
                            Text(d.kind + (d.id == Device.id ? " · this one" : ""))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("· last seen " + WaitingForPlanView.when(d.lastMet) + " · \(d.appVersion) (\(d.build))")
                                .font(.footnote).foregroundStyle(Theme.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("icloud-device-" + d.kind)
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("icloud-devices")

                SectionHeading(text: "What is shared")
                Text("The plan, everything you log and change, and your morning and how-hard answers are the same on your iPhone, iPad and Mac. Apple Health numbers come from your iPhone. The Training calendar and Dropbox stay on your iPhone.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SectionHeading(text: "Before iCloud")
                SettingsRow(title: "Copy from before iCloud",
                            sub: store.beforeICloudCopy == nil
                                ? "None on this \(Device.word): it had no plan of its own before iCloud."
                                : "The plan on this \(Device.word) as it was before it first met iCloud. Kept for good.",
                            action: store.beforeICloudCopy == nil ? nil : ("Share", { beforeCopy = store.beforeICloudCopy }),
                            actionID: "icloud-before-copy")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("iCloud").font(.headline).accessibilityIdentifier("icloud-title")
            }
        }
        .sheet(item: $beforeCopy) { url in ShareSheet(items: [url]) }
        // Said once: after he has seen it here, the words about what was taken out go.
        .onDisappear { store.cloud.takenNoticeSeen() }
    }

    /* The device list, iPhone first, then iPad, then Mac. */
    private func devices(_ cloud: PlanCloud) -> [PlanCloud.DeviceFile] {
        let order = ["iPhone": 0, "iPad": 1, "Mac": 2]
        return cloud.devices.sorted { (order[$0.kind] ?? 3, $0.lastMet) < (order[$1.kind] ?? 3, $1.lastMet) }
    }

    private func detail(_ cloud: PlanCloud) -> String {
        switch cloud.status {
        case .off:
            return Device.isMac
                ? "Sign in to iCloud on this Mac (System Settings → your name → iCloud), then open Triathlon again. Until then the plan on this Mac is not shared."
                : "Sign in to iCloud on this \(Device.word) (Settings → your name → iCloud), then open Triathlon again. Until then the plan on this \(Device.word) is not shared."
        case .working:
            if let why = cloud.waitingWhy { return why }
            return store.planLivesHere || !Device.isPhone ? "Your plan is on its way between your devices." :
                "Your plan still lives in Excel on this iPhone, so it is not shared yet."
        case .noted(let at, _):
            return "Last met iCloud " + WaitingForPlanView.when(at) + "."
        case .same(let at):
            if !store.planLivesHere && Device.isPhone { return "Your morning answers are shared. The plan is shared once it lives in this app." }
            return "Last met iCloud " + (at.map(WaitingForPlanView.when) ?? "just now") + "."
        case .problem:
            if cloud.otherPlan != nil {
                return "Your iCloud holds a plan from another move into the app. Look at both below and choose the one to keep — the other is kept in Settings › Safety copies, where it can be put back."
            }
            return "Nothing on this \(Device.word) was changed. " + (cloud.lastMet.map { "Last met iCloud " + WaitingForPlanView.when($0) + "." } ?? "")
        }
    }
}

/* The sync dot: grey off, orange on its way, green the same everywhere, red a problem. Never shown without its words. */
struct StatusDot: View {
    let status: SyncStatus
    var body: some View {
        Circle().fill(status.tint).frame(width: 9, height: 9)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            .accessibilityHidden(true)
    }
}

/*
 * Two plans that were moved into the app separately (two Excel imports):
 * never joined by the app. Side by side, with what each holds; he picks one.
 * Taking the other plan replaces the one on this device, so it asks first,
 * with both plans in words. The one not kept goes into Safety copies.
 */
struct TwoPlansView: View {
    let mine: PlanBook
    let theirs: PlanBook
    /* "your Mac" — or "your other devices" when it cannot be told. */
    let theirsFrom: String
    let choose: (_ keepThisDevice: Bool) -> Void
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Two different plans")
            HStack(alignment: .top, spacing: 10) {
                side("On this \(Device.word)", mine, id: "two-plans-left") { choose(true) }
                side("In iCloud, from \(theirsFrom)", theirs, id: "two-plans-right") { confirming = true }
            }
            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use that plan here?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("On this \(Device.word): \(Self.words(mine)).\nIn iCloud, from \(theirsFrom): \(Self.words(theirs)).\nThe plan on this \(Device.word) is replaced by the one from \(theirsFrom). It is kept in Settings › Safety copies, where it can be put back.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("two-plans-words")
                    HStack(spacing: 10) {
                        Button { confirming = false } label: {
                            Text("Cancel").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("two-plans-cancel")
                        Button { confirming = false; choose(false) } label: {
                            Text("Use that plan here").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.danger)
                        .accessibilityIdentifier("two-plans-confirm")
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            }
        }
    }

    private static func done(_ book: PlanBook) -> Int {
        book.sessions.filter { $0.discipline.id != "rest" && $0.loggedInSheet && !$0.missed }.count
    }

    private static func last(_ book: PlanBook) -> Date {
        book.stamps.values.filter { $0.timeIntervalSince1970 > 1_600_000_000 }.max() ?? book.origin.takenAt
    }

    /* "214 sessions, 31 done, last change Wed 25 Nov 2026, 09:12" */
    static func words(_ book: PlanBook) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM yyyy, HH:mm"
        return "\(book.sessions.count) sessions, \(done(book)) done, last change \(f.string(from: last(book)))"
    }

    private func side(_ title: String, _ book: PlanBook, id: String, use: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            Text("\(book.sessions.count) sessions · \(Self.done(book)) done").font(.footnote).foregroundStyle(Theme.secondary)
            Text("last change " + WaitingForPlanView.when(Self.last(book))).font(.footnote).foregroundStyle(Theme.secondary)
            Text("moved in " + SettingsView.dayMonthYear(book.origin.takenAt)).font(.footnote).foregroundStyle(Theme.secondary)
            Button(action: use) {
                Text("Use this one").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent).tint(Theme.today)
            .padding(.top, 4)
            .accessibilityIdentifier(id + "-use")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}
