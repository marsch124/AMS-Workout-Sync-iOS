import SwiftUI
import PhotosUI
import UIKit
import WorkoutCore

/* The strip on a session or an extra: thumbnails, then Add from the library or the camera. */
struct PhotoStrip: View {
    @ObservedObject private var photos = PhotoStore.shared
    let owner: PhotoOwner
    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var viewing: PhotoMeta?

    private var mine: [PhotoMeta] { photos.photos(for: owner) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: mine.isEmpty ? "Photos" : "Photos · \(mine.count)")
            if !mine.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(mine) { photo in
                        Button { viewing = photo } label: {
                            Thumb(id: photo.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $picked, maxSelectionCount: 6, matching: .images) {
                    Label { Text("Add photo") } icon: { Glyph(name: "icon-plus", size: 18) }
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered).controlSize(.small).tint(Theme.today)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: {
                        Label { Text("Camera") } icon: { Glyph(name: "icon-camera", size: 18) }
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(Theme.today)
                }
            }
            Text("Kept on this phone only — not in the workbook, not in Dropbox. Save them out from Settings → Photos.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { photos.add(data, to: owner) }
                }
                picked = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in if let data { photos.add(data, to: owner) } }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photo: photo, all: mine)
        }
    }
}

struct Thumb: View {
    let id: String
    var body: some View {
        Group {
            if let image = PhotoStore.shared.image(id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.surface2
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/* Full size, swipe between a session's pictures, share or delete. */
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var photos = PhotoStore.shared
    let photo: PhotoMeta
    let all: [PhotoMeta]
    @State private var current: String = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(all) { p in
                    Group {
                        if let image = photos.image(p.id) {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            Text("This picture could not be read.").foregroundStyle(.white)
                        }
                    }
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let data = photos.data(current), let image = UIImage(data: data) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Session photo", image: Image(uiImage: image))) {
                            Glyph(name: "icon-share", size: 20)
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Text("Delete") }
                }
            }
            .confirmationDialog("Delete this photo? It is the only copy.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    photos.remove(current)
                    if let next = photos.photos(for: PhotoOwner(key: photo.workoutKey, disciplineId: photo.disciplineId, dayKey: photo.dayKey, title: photo.title, sheet: photo.sheet)).first {
                        current = next.id
                    } else {
                        dismiss()
                    }
                }
                Button("Keep it", role: .cancel) {}
            }
            .onAppear { current = photo.id }
        }
        .preferredColorScheme(.dark)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            parent.onImage(image?.jpegData(compressionQuality: 0.95))
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImage(nil)
            parent.dismiss()
        }
    }
}

/* A small camera and a count on a card, when a session or extra has pictures. */
struct PhotoCountPill: View {
    let count: Int
    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Glyph(name: "icon-camera", size: 14)
                Text("\(count)")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface2))
        }
    }
}

/* An extra opened on its own: what it was, and its photographs. */
struct ExtraDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let extra: ExtraSummary

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ExtraCard(extra: extra)
                    PhotoStrip(owner: PhotoOwner(extra: extra))
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Extra activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

/* Settings → Photos: how many, how big, save them out, bring the web app's in, delete. */
struct PhotoSettings: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var photos = PhotoStore.shared
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var confirmDeleteAll = false
    @State private var note: String?

    private var owners: [PhotoOwner] { store.displayed.map(PhotoOwner.init) + store.allExtras.map { PhotoOwner(extra: $0) } }

    var body: some View {
        let orphans = photos.orphans(owners: owners).count
        let mb = Double(photos.totalBytes) / 1_048_576
        SettingsRow(title: "\(photos.index.count) photo\(photos.index.count == 1 ? "" : "s") · \(String(format: "%.1f", mb)) MB",
                    sub: "On this phone only, and in the iPhone's own backup. Not in the workbook, not in Dropbox."
                        + (orphans > 0 ? " \(orphans) belong to a session that has since changed — still here, still exported." : ""))
        HStack(spacing: 8) {
            Button("Save all") {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("workout-photos-\(PlanView.todayKey()).zip")
                try? photos.exportZip().write(to: url)
                exportURL = url
            }
            .settingsButton(tint: Theme.today)
            .disabled(photos.index.isEmpty)
            Button("Bring in a zip") { importing = true }
                .settingsButton(tint: Theme.today)
            if !photos.index.isEmpty {
                Button("Delete all") { confirmDeleteAll = true }
                    .settingsButton(tint: Theme.danger)
            }
            Spacer(minLength: 0)
        }
        if let note { Text(note).font(.footnote).foregroundStyle(Theme.secondary) }
        Text("Save all writes every picture into one zip you can keep in Files. Bring in a zip takes one back, each picture to its session by the day and sport in its name.")
            .font(.caption).foregroundStyle(Theme.secondary)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let r = try photos.importZip(data, plan: store.displayed, extras: store.allExtras)
                    note = "\(r.imported) photo\(r.imported == 1 ? "" : "s") brought in" + (r.unplaced > 0 ? ", \(r.unplaced) without a matching session (kept, counted, exported)." : ".")
                } catch {
                    note = "That zip could not be read: \(error.localizedDescription)"
                }
            }
            .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
            .confirmationDialog("Delete every photo? They are the only copies.", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all \(photos.index.count)", role: .destructive) { photos.removeAll() }
                Button("Keep them", role: .cancel) {}
            }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
