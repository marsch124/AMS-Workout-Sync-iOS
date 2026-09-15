import SwiftUI
import WorkoutCore

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
