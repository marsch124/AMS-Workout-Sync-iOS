import SwiftUI
import UniformTypeIdentifiers
import WorkoutCore

/*
 * Settings, in the order they matter: which plan the app is reading and
 * writing, what is still on its way, then the rest.
 *
 * He found "Choose plan" beside "Choose in Files" confusing, and the buttons
 * too big beside the headings. So there is one way to pick the plan once
 * Dropbox is connected — the Files picker only remains as a read-only way in
 * before that — and the buttons are small text buttons on the row they act
 * on, with one prominent button per screen at most.
 */
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var picking = false
    @State private var browsing = false
    @State private var connecting = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)
                        .accessibilityIdentifier("settings-title")

                    SectionHeading(text: "Your plan")
                    if Dropbox.shared.isConnected {
                        SettingsRow(title: store.fileName.isEmpty ? "No plan chosen yet" : store.fileName,
                                    sub: planLine,
                                    action: store.dropboxPath == nil ? nil : ("Change", { browsing = true }))
                        if store.dropboxPath == nil {
                            Button { browsing = true } label: {
                                Text("Choose your plan in Dropbox").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.today)
                        } else {
                            Button("Read it again now") { store.refresh() }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.bordered).controlSize(.small).tint(Theme.today)
                        }
                    } else {
                        SettingsRow(title: "Not connected to Dropbox",
                                    sub: "Connect, and the app reads your plan from Dropbox and writes your logging into it.")
                        Button { Task { await connect() } } label: {
                            Text(connecting ? "Connecting…" : "Connect Dropbox").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.today).disabled(connecting)
                        Button("Or open a copy from Files, read only") { picking = true }
                            .font(.subheadline).tint(Theme.secondary)
                        if !store.fileName.isEmpty {
                            SettingsRow(title: store.fileName, sub: "Read only · " + readLine)
                        }
                    }
                    if let problem = problem ?? store.lastProblem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                    }

                    if Dropbox.shared.isConnected {
                        SectionHeading(text: "Waiting to sync")
                        if store.queue.isEmpty {
                            SettingsRow(title: "Nothing waiting",
                                        sub: store.syncing ? "Sending…" : "Everything logged on this phone is in Dropbox")
                        } else {
                            ForEach(store.queue) { q in
                                SettingsRow(title: q.extra.map { Extras.activity($0.activity).label + " · extra" } ?? q.title,
                                            sub: Dates.short(q.dayKey) + " · " + (q.lastError ?? "waiting"),
                                            action: ("Discard", { store.discard(q.id) }))
                            }
                            Button(store.syncing ? "Sending…" : "Send now") { store.syncNow() }
                                .font(.subheadline.weight(.semibold)).tint(Theme.today).disabled(store.syncing)
                        }
                    }

                    if let mapping = store.mapping {
                        SectionHeading(text: "How the sheet is read")
                        SettingsRow(title: mapping.sheets.joined(separator: ", "),
                                    sub: "\(store.plan.count) sessions · headings on row \(mapping.headerRow)")
                        SettingsRow(title: "Durations in \(mapping.units.duration), distances in \(mapping.units.distance)",
                                    sub: "Done is written \(mapping.doneValue), missed \(mapping.missedValue)")
                    }

                    SectionHeading(text: "Your zones").id("zones")
                    NavigationLink { ZonesView() } label: {
                        SettingsRow(title: zonesTitle, sub: zonesSub, chevron: true)
                    }
                    .buttonStyle(.plain)

                    SectionHeading(text: "Colours and shapes")
                    VStack(alignment: .leading, spacing: 10) {
                        WeekKey(days: [])
                        Text("Also one tap away: tap the This week card on Today.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))

                    SectionHeading(text: "Extra activities")
                    NavigationLink { ExtrasListView() } label: {
                        SettingsRow(title: "\(store.allExtras.count) recorded",
                                    sub: "Walks, yoga, breathing — everything outside the plan, newest first", chevron: true)
                    }
                    .buttonStyle(.plain)

                    SectionHeading(text: "Photos")
                    PhotoSettings()

                    SectionHeading(text: "Apple Health")
                    HealthSettings()

                    SectionHeading(text: "Calendar").id("calendar")
                    CalendarSettings()

                    SectionHeading(text: "Dropbox")
                    if Dropbox.shared.isConnected {
                        SettingsRow(title: Dropbox.shared.account.isEmpty ? "Connected" : Dropbox.shared.account,
                                    sub: "The app can read and write only the files you point it at.",
                                    action: ("Disconnect", {
                                        Dropbox.shared.disconnect()
                                        store.dropboxPath = nil
                                    }))
                    } else {
                        SettingsRow(title: "Not connected", sub: "Use Connect Dropbox above.")
                    }

                    SectionHeading(text: "This app")
                    NavigationLink { GuideView() } label: {
                        SettingsRow(title: "How this works", sub: "The week strip, logging, syncing and what keeps your plan safe", chevron: true)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { WhatsNewView() } label: {
                        SettingsRow(title: "What’s new", sub: "AMS Workout Sync \(version)", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-whats-new")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            #if DEBUG
            .onAppear {
                // A screenshot of one section, far down the page.
                if let id = ProcessInfo.processInfo.environment["AMSWS_SCROLL"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(id, anchor: .top) }
                }
            }
            #endif
            }
        }
        .workbookPicker(isPresented: $picking)
        .sheet(isPresented: $browsing) {
            DropboxBrowser(path: "") { file in
                browsing = false
                store.chooseDropbox(file)
            }
        }
    }

    private var planLine: String {
        guard store.dropboxPath != nil else { return "Pick the workbook the app should log into" }
        let isTest = store.fileName.lowercased().contains("test")
        return (isTest ? "TEST COPY · " : "") + readLine
    }

    private var readLine: String {
        guard let at = store.readAt else { return "Not read yet" }
        let prefix = store.fromCache ? "Copy on this phone, read " : "Read "
        if Date().timeIntervalSince(at) < 60 { return prefix + "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return prefix + f.localizedString(for: at, relativeTo: Date())
    }

    /* "LTHR 150 bpm · CSS 121 sec/100 m · Weight 80 kg" (invented) — the sheet's own labels, shortened. */
    private var zonesTitle: String {
        guard let z = store.zones else { return "No zones sheet in this workbook" }
        let known = z.current.filter { !$0.value.isEmpty }
        if known.isEmpty { return "No test entered yet" }
        return known.map { row in
            let parts = row.label.split(separator: "(", maxSplits: 1)
            let name = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? row.label
            let unit = parts.count > 1 ? " " + String(parts[1]).replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces) : ""
            return name + " " + row.value + unit
        }.joined(separator: " · ")
    }

    private var zonesSub: String {
        guard let z = store.zones else { return "The app reads the Test Results & Zones sheet for what Z2 means. This workbook has none." }
        return (z.latestTest.isEmpty ? "" : "From " + z.latestTest + ". ") + "Tap a session’s Z2 or Z4–Z5 for what it means for you."
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func connect() async {
        connecting = true
        problem = nil
        do {
            _ = try await Dropbox.shared.connect()
            browsing = true
        } catch DropboxError.cancelled {
        } catch {
            problem = error.localizedDescription
        }
        connecting = false
    }
}

/* A row with a title, a grey line under it and, at most, one small button on the right. */
struct SettingsRow: View {
    /* Buttons that take something away are red; every other one is green. */
    static let takesAway: Set<String> = ["Disconnect", "Discard", "Stop", "Take them out"]

    let title: String
    let sub: String
    var action: (String, () -> Void)? = nil
    var chevron = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Text(sub).font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(SettingsRow.takesAway.contains(action.0) ? Theme.danger : Theme.today)
            }
            if chevron {
                Text("›").font(.title2).foregroundStyle(Theme.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

extension View {
    func workbookPicker(isPresented: Binding<Bool>) -> some View {
        modifier(WorkbookPicker(isPresented: isPresented))
    }
}

struct WorkbookPicker: ViewModifier {
    @EnvironmentObject var store: Store
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first { store.choose(url) }
        }
    }
}


struct HealthSettings: View {
    @ObservedObject private var health = HealthImport.shared

    var body: some View {
        switch health.status {
        case .unavailable:
            SettingsRow(title: "Not available on this device", sub: "Apple Health is iPhone only.")
        case .asked where health.enabled:
            SettingsRow(title: "In use",
                        sub: "The log form offers the day’s workouts from Health to fill the boxes. Health is only read, never written.",
                        action: ("Stop", { health.enabled = false }))
            Text("Stop means the app never asks Health for anything again. To also take the permission away, open the Health app → your picture → Apps → Workout Sync.")
                .font(.caption).foregroundStyle(Theme.secondary)
            Button("Open the Health app") {
                if let url = URL(string: "x-apple-health://") { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).controlSize(.small).tint(Theme.today)
        case .asked:
            SettingsRow(title: "Not in use",
                        sub: "The app does not read Health. The permission may still be granted in the Health app.",
                        action: ("Use again", { health.enabled = true }))
        case .denied:
            SettingsRow(title: "Could not ask", sub: "iOS did not let the app ask for access. Open the Health app → your picture → Apps → Workout Sync.")
        case .unknown:
            SettingsRow(title: "Not connected",
                        sub: "Let the app read your workouts, heart rate and distances, and the log form can fill itself from what your Garmin sent to Health. Optional.",
                        action: ("Connect", { Task { await health.requestAccess(); health.enabled = true } }))
        }
    }
}


/*
 * The plan in the Calendar app. One button in, one button out; the hour the
 * day's first session starts at is the only setting.
 */
struct CalendarSettings: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var cal = TrainingCalendar.shared
    @State private var start = Date()

    var body: some View {
        if cal.enabled && cal.status == .granted {
            SettingsRow(title: "\(cal.count) sessions and rest days in your Training calendar",
                        sub: updatedLine,
                        action: ("Take them out", { cal.disable() }))
            HStack {
                Text("The day’s first session starts at").font(.subheadline).foregroundStyle(Theme.text)
                Spacer()
                DatePicker("", selection: $start, displayedComponents: .hourAndMinute).labelsHidden().tint(Theme.today)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .onAppear { start = Self.date(minutes: cal.startMinutes); cal.refreshStatus() }
            .onChange(of: start) { _, d in
                let m = Self.minutes(d)
                if m != cal.startMinutes { cal.startMinutes = m; store.calendarChanged() }
            }
            Text("Every session from today to the end of the plan, each as long as it is planned, one after the other on a day with two; a rest day is an all-day event. Six in the morning stays six in the morning wherever the phone is. The Training calendar is the app’s own: from today onwards it holds the plan and nothing else, and Take them out removes the calendar.")
                .font(.caption).foregroundStyle(Theme.secondary)
        } else if cal.status == .denied {
            SettingsRow(title: "Not allowed",
                        sub: "iOS is not letting the app write to your calendar. Settings → Apps → Workout Sync → Calendars → Full Access.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).controlSize(.small).tint(Theme.today)
        } else {
            SettingsRow(title: "Not in your calendar",
                        sub: "Put every session from today onwards into a Training calendar at 06:00, each as long as it is planned, and keep them right when sessions move.",
                        action: ("Put them in", { Task { await cal.enable(); store.calendarChanged() } }))
        }
        if let p = cal.problem {
            Text(p).font(.footnote).foregroundStyle(Theme.danger)
        }
    }

    private var updatedLine: String {
        if cal.busy { return "Updating…" }
        guard let at = cal.lastSync else { return "Not written yet" }
        if Date().timeIntervalSince(at) < 60 { return "Updated just now · from today to the end of the plan" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Updated " + f.localizedString(for: at, relativeTo: Date()) + " · from today to the end of the plan"
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 6) * 60 + (c.minute ?? 0)
    }
}
