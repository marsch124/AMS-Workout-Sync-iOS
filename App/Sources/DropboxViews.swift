import SwiftUI
import WorkoutCore

/* Settings → Dropbox: connect, pick the plan inside his Dropbox, disconnect. */
struct DropboxSection: View {
    @EnvironmentObject var store: Store
    @State private var connected = Dropbox.shared.isConnected
    @State private var account = Dropbox.shared.account
    @State private var working = false
    @State private var problem: String?
    @State private var browsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Dropbox")
            if connected {
                SettingsRow(title: account.isEmpty ? "Connected" : account,
                            sub: store.dropboxPath.map { "Plan: " + $0 } ?? "Choose which workbook is your plan")
                HStack(spacing: 10) {
                    Button("Choose plan") { browsing = true }
                        .buttonStyle(.borderedProminent).tint(Theme.today)
                    Button("Disconnect") {
                        Dropbox.shared.disconnect()
                        store.dropboxPath = nil
                        connected = false
                    }
                    .buttonStyle(.bordered).tint(Theme.danger)
                }
            } else {
                SettingsRow(title: "Not connected",
                            sub: "Connecting lets the app fetch your plan directly. Logging from the iPhone comes next.")
                Button {
                    Task { await connect() }
                } label: {
                    Text(working ? "Connecting…" : "Connect Dropbox").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(Theme.today).disabled(working)
            }
            if let problem { Text(problem).font(.footnote).foregroundStyle(Theme.danger) }
        }
        .sheet(isPresented: $browsing) {
            DropboxBrowser(path: "") { file in
                browsing = false
                store.chooseDropbox(file)
            }
        }
    }

    private func connect() async {
        working = true
        problem = nil
        do {
            account = try await Dropbox.shared.connect()
            connected = true
            browsing = true
        } catch DropboxError.cancelled {
        } catch {
            problem = error.localizedDescription
        }
        working = false
    }
}

struct SettingsRow: View {
    let title: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            Text(sub).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

/* Folders and .xlsx files only; tap a folder to go in, a workbook to choose it. */
struct DropboxBrowser: View {
    let path: String
    let onChoose: (DropboxFile) -> Void

    var body: some View {
        NavigationStack {
            DropboxFolder(path: path, title: "Dropbox", onChoose: onChoose)
        }
    }
}

struct DropboxFolder: View {
    let path: String
    let title: String
    let onChoose: (DropboxFile) -> Void
    @State private var files: [DropboxFile]?
    @State private var problem: String?

    var body: some View {
        List {
            if let problem { Text(problem).foregroundStyle(Theme.danger) }
            if let files {
                if files.isEmpty { Text("No folders or workbooks here.").foregroundStyle(Theme.secondary) }
                ForEach(files) { file in
                    if file.isFolder {
                        NavigationLink(file.name) {
                            DropboxFolder(path: file.pathLower, title: file.name, onChoose: onChoose)
                        }
                    } else {
                        Button { onChoose(file) } label: {
                            HStack {
                                Glyph(name: "icon-plan", size: 20).foregroundStyle(Theme.today)
                                Text(file.name).foregroundStyle(Theme.text)
                            }
                        }
                    }
                }
            } else if problem == nil {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .task {
            do { files = try await Dropbox.shared.list(path) }
            catch { problem = error.localizedDescription }
        }
    }
}
