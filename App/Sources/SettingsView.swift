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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)

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
                        SettingsRow(title: "What’s new", sub: "Workout Sync for iPhone \(version)", chevron: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
                    .tint(action.0 == "Disconnect" || action.0 == "Discard" ? Theme.danger : Theme.today)
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
