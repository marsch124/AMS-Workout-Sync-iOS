import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import WorkoutCore

/*
 * Swim video check (round 30, pick 17). He chooses a video of one pool length
 * from Photos; the app takes six still pictures from it and shows them; one
 * button sends them to Claude (his own key, about 3 cents) and exactly three
 * plain tips on the stroke come back, each linked to a drill card where one
 * fits. Six still pictures go to Anthropic; the video stays on this device and
 * no picture is kept. Only the tips are kept, on the shelf by day
 * (coach/swimcheck/<day>), so they follow him between devices.
 */

/* A video picked from Photos, copied to a temporary file and deleted again after the pictures are taken. */
struct CoachMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("coach-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return CoachMovie(url: copy)
        }
    }
}

extension Claude {
    /* Six still pictures from a video file: the moments SwimCheck chooses, no larger than the check needs. */
    static func frames(from url: URL) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: SwimCheck.pictureSide, height: SwimCheck.pictureSide)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        var out: [UIImage] = []
        for t in SwimCheck.frameTimes(duration: duration) {
            if let (cg, _) = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) { out.append(UIImage(cgImage: cg)) }
        }
        return out
    }
}
/* A name to hang the helpers on. */
enum Claude {}

@MainActor
final class SwimCheckModel: ObservableObject {
    @Published var frames: [UIImage] = []
    @Published var tips: [SwimTip]?
    @Published var busy = false
    @Published var message: String?
    @Published var preparing = false

    init() {
        #if DEBUG
        // AMSWS_SWIM_CHECK=1: six invented pictures; =tips: with three invented tips too (no key, no network).
        if let mode = ProcessInfo.processInfo.environment["AMSWS_SWIM_CHECK"] {
            frames = (1...SwimCheck.frameCount).map { Self.invented($0) }
            if mode == "tips" { tips = SwimCheck.invented }
        }
        #endif
    }

    func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        preparing = true; tips = nil; message = nil
        defer { preparing = false }
        guard let movie = try? await item.loadTransferable(type: CoachMovie.self) else {
            message = "That video could not be opened."
            return
        }
        frames = await Claude.frames(from: movie.url)
        try? FileManager.default.removeItem(at: movie.url)
        if frames.isEmpty { message = "No pictures could be taken from that video." }
    }

    func send(day: String) async {
        guard !busy, !frames.isEmpty else { return }
        busy = true; message = nil
        let client = ClaudeClient.shared
        let base64 = frames.compactMap { $0.jpegData(compressionQuality: 0.6)?.base64EncodedString() }
        let result = await client.run(kind: "swimcheck", label: "Looked at six pictures of a swim length",
                                      body: SwimCheck.body(jpegBase64: base64), fake: SwimCheck.invented, read: SwimCheck.read)
        busy = false
        switch result {
        case .answer(let t):
            tips = t
            keep(t, day: day)
        case .notPassed: message = SwimCheck.didNotPass
        case .none: message = client.trouble == nil ? SwimCheck.nothingCame : nil
        }
    }

    /* The tips only, never a picture. */
    private func keep(_ tips: [SwimTip], day: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AMSWS_SWIM_CHECK"] != nil { return }   // a picture never keeps invented tips
        #endif
        let key = SwimCheck.shelfKey(day: day)
        var today = ShelfStore.shared.value(SwimCheckDay.self, for: key) ?? SwimCheckDay()
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        today.checks.append(SwimCheckEntry(time: f.string(from: Date()), tips: tips))
        _ = ShelfStore.shared.set(today, for: key)
    }

    #if DEBUG
    private static func invented(_ n: Int) -> UIImage {
        let size = CGSize(width: 320, height: 200)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let hues: [UIColor] = [.systemBlue, .systemIndigo, .systemPurple, .systemOrange, .systemPink, .systemBrown]
            hues[(n - 1) % hues.count].withAlphaComponent(0.35).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.8).setStroke()
            let p = UIBezierPath()
            p.lineWidth = 6; p.lineCapStyle = .round
            p.move(to: CGPoint(x: 40, y: 120)); p.addLine(to: CGPoint(x: 230, y: 112 - CGFloat(n) * 3))
            p.move(to: CGPoint(x: 230, y: 112 - CGFloat(n) * 3)); p.addLine(to: CGPoint(x: 290, y: 130 - CGFloat(n) * 6))
            p.stroke()
        }
    }
    #endif
}

struct SwimCheckPage: View {
    var inSheet = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var client = ClaudeClient.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @StateObject private var model = SwimCheckModel()
    @State private var picked: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Swim video check").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.plan)
                    .accessibilityIdentifier("swim-check-title")
                VStack(alignment: .leading, spacing: 2) {
                    Text("ONE POOL LENGTH, THREE TIPS").font(.caption.weight(.bold)).tracking(0.8).opacity(0.85)
                    Text("Film one length of front crawl from the side of the pool, choose it here, and Claude gives three plain tips on your stroke.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.plan.deepHead))

                PhotosPicker(selection: $picked, matching: .videos, photoLibrary: .shared()) {
                    Text(model.frames.isEmpty ? "Choose a video" : "Choose another video")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.plan.deepHead)
                .accessibilityIdentifier("swim-check-choose")
                .onChange(of: picked) { _, item in Task { await model.load(item) } }
                if model.preparing {
                    Text("Taking six pictures\u{2026}").font(.footnote).foregroundStyle(Theme.secondary)
                }

                if !model.frames.isEmpty { frames }
                if let tips = model.tips { tipCards(tips) }
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("swim-check-message")
                }
                past
            }
            .padding(16)
            .readableWidth(760)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("swim-check-done")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swim-check-page")
    }

    private var frames: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(model.frames.enumerated()), id: \.offset) { i, image in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(height: 78).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Text(String(i + 1)).font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Circle().fill(Theme.plan)).padding(4)
                        }
                        .accessibilityIdentifier("swim-check-frame-\(i + 1)")
                }
            }
            Text(SwimCheck.sentWords).font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("swim-check-sent")
            if model.tips == nil { sendArea }
        }
    }

    @ViewBuilder private var sendArea: some View {
        if let trouble = client.trouble {
            Text(trouble.restLine).font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("swim-check-trouble")
        } else if !client.canWrite {
            Text(SwimCheck.notOn).font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("swim-check-trouble")
        } else {
            Button {
                Task { await model.send(day: store.today) }
            } label: {
                Text(model.busy ? "Looking\u{2026}" : SwimCheck.buttonWords).font(.body.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.plan.deepHead)
            .disabled(model.busy)
            .accessibilityIdentifier("swim-check-send")
        }
    }

    private func tipCards(_ tips: [SwimTip]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(tips.enumerated()), id: \.offset) { i, tip in
                let hue = CoachHue.all[(i * 2) % CoachHue.all.count]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(i + 1)).font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(hue.fill))
                        Text(tip.text).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                    if let id = tip.drill, let card = DrillCards.card(id) {
                        NavigationLink { DrillCardPage(card: card) } label: { Text("Drill card: " + card.name) }
                            .settingsButton(tint: hue.fill)
                            .accessibilityIdentifier("swim-tip-drill-\(i + 1)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hue.tile))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("swim-tip-\(i + 1)")
            }
        }
    }

    /* Earlier checks by day, tips text only. */
    @ViewBuilder private var past: some View {
        let days = shelf.keys(prefix: "coach/swimcheck/").compactMap { key -> (day: String, value: SwimCheckDay)? in
            shelf.value(SwimCheckDay.self, for: key).map { (String(key.dropFirst("coach/swimcheck/".count)), $0) }
        }
        let rows = SwimCheck.listing(days)
        if !rows.isEmpty {
            SectionHeading(text: "Earlier checks")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(Dates.short(row.day).uppercased() + " \u{00B7} " + row.entry.time)
                        .font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.plan)
                    ForEach(Array(row.entry.tips.enumerated()), id: \.offset) { _, t in
                        Text(t.text).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("swim-check-past-row")
            }
        }
    }
}

/* Picture switches for the three Coach pages (DEBUG only). */
struct CoachDebugScreens: View {
    @EnvironmentObject var store: Store

    var body: some View {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["AMSWS_DRILL_CARDS"] != nil {
            NavigationStack { DrillCardsPage() }.background(Theme.bg.ignoresSafeArea())
        }
        if let id = env["AMSWS_DRILL_CARD"], let card = DrillCards.card(id) ?? DrillCards.all.first {
            NavigationStack { DrillCardPage(card: card) }.background(Theme.bg.ignoresSafeArea())
        }
        if env["AMSWS_SWIM_CHECK"] != nil {
            NavigationStack { SwimCheckPage() }.background(Theme.bg.ignoresSafeArea())
        }
        if env["AMSWS_BLOCK_CARD"] != nil {
            ScrollView { BlockIntroCard().padding(16) }.background(Theme.bg.ignoresSafeArea())
        }
        #endif
    }
}
