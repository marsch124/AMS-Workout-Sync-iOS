import SwiftUI
import UIKit

/*
 * 2.22: How this works as pictures and short lines (his rule, 27 Nov 2026: "No human can read this stuff").
 * Each part = a title, ONE picture of the real screen with invented values (by day and by night, made by
 * tools/guide-pictures.py) and 3–7 lines of one sentence each. Busy pictures carry numbered circles; the line
 * with the same number explains that spot. A tap on a picture opens it bigger in a sheet, with its circles and lines.
 * Same idea as AMS SimCard Menu 0.4.1, with a sheet instead of a window.
 */

/// A numbered circle on a picture, in points of that picture.
struct GuideMark: Identifiable {
    let n: Int
    let x: CGFloat
    let y: CGFloat
    var id: Int { n }
    init(_ n: Int, _ x: CGFloat, _ y: CGFloat) { self.n = n; self.x = x; self.y = y }
}

/// One line of a part: with a number (it explains that circle), without one, or a small heading (Signs in this app).
struct GuideLine: Identifiable {
    let id = UUID()
    let n: Int?
    let text: String
    var head = false

    static func n(_ n: Int, _ text: String) -> GuideLine { GuideLine(n: n, text: text) }
    static func plain(_ text: String) -> GuideLine { GuideLine(n: nil, text: text) }
    static func head(_ text: String) -> GuideLine { GuideLine(n: nil, text: text, head: true) }
}

struct GuideSection: Identifiable {
    let id: String
    let title: String
    var picture: String? = nil
    var marks: [GuideMark] = []
    let lines: [GuideLine]

    /// Each part's heading in the colour of the part of the app it is about.
    var hue: Color {
        switch id {
        case "intro", "neighbours", "today", "todaydown", "suggest", "stop": return Theme.today
        case "moreways": return Theme.plan
        case "signs": return Theme.progress
        case "session", "logform", "done", "sessions", "extra", "week", "month", "year": return Theme.plan
        case "body": return Theme.body
        case "progress", "zones": return Theme.progress
        case "race", "gear": return Theme.danger
        case "planmaker": return Theme.season
        default: return Theme.settings
        }
    }
}

/// The pictures, at 2 pixels a point, by day and by night (App/Resources/Guide/guide-<name>-day|night.jpg).
@MainActor
enum GuideImages {
    static let pixelsPerPoint: CGFloat = 2
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: String, dark: Bool) -> UIImage? {
        let file = "guide-\(name)-\(dark ? "night" : "day")"
        if let kept = cache[file] { return kept }
        guard let url = Bundle.main.url(forResource: file, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data, scale: pixelsPerPoint) else { return nil }
        cache[file] = image
        return image
    }

    /// The picture's size on the real screen, in points.
    static func size(_ name: String) -> CGSize? { image(name, dark: false)?.size }
}

/// The numbered circle: dark with a white ring by day, white with a dark ring by night, so it shows on any colour.
struct GuideNumber: View {
    let n: Int
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(String(n))
            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
            .foregroundStyle(dark ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(dark ? Color.white : Color(white: 0.12)))
            .overlay(Circle().stroke(dark ? Color.black.opacity(0.6) : Color.white, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// A picture with its numbered circles, as wide as it may be (never wider than the real screen times `most`).
struct GuidePicture: View {
    let name: String
    let marks: [GuideMark]
    /// 1 = the size of the real screen; the bigger view goes further.
    var most: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let image = GuideImages.image(name, dark: scheme == .dark) {
            let natural = image.size
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            Image(uiImage: image).resizable().interpolation(.high)
                .aspectRatio(natural, contentMode: .fit)
                .frame(maxWidth: natural.width * most)
                .clipShape(shape)
                .overlay(shape.stroke(Theme.border, lineWidth: 1))
                .overlay {
                    GeometryReader { geo in
                        let scale = geo.size.width / natural.width
                        ForEach(marks) { mark in
                            GuideNumber(n: mark.n, size: 20 * min(max(scale, 0.85), 1.4))
                                .position(x: mark.x * scale, y: mark.y * scale)
                        }
                    }
                }
        }
    }
}

/// The short lines of a part: a numbered circle before a line that explains one, a dash before the others.
struct GuideLines: View {
    let lines: [GuideLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(lines) { line in
                if line.head {
                    Text(line.text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let n = line.n {
                            GuideNumber(n: n, size: 18)
                        } else {
                            Text("\u{2013}").foregroundStyle(Theme.secondary).frame(width: 18)
                        }
                        Text(line.text).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One part on the guide page: its title, its picture (a tap opens it bigger) and its lines.
/// A phone picture sits beside its lines on a wide screen; a wide picture (the iPad's Plan page) stays above them.
struct GuidePartView: View {
    let section: GuideSection
    let open: (GuideSection) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title).font(.title3.weight(.bold)).foregroundStyle(section.hue)
                .accessibilityAddTraits(.isHeader)
            if let name = section.picture, let natural = GuideImages.size(name) {
                if sizeClass == .regular && natural.width < 500 {
                    HStack(alignment: .top, spacing: 16) {
                        picture(name).frame(width: min(natural.width, 340))
                        GuideLines(lines: section.lines)
                    }
                } else {
                    picture(name)
                    GuideLines(lines: section.lines)
                }
            } else {
                GuideLines(lines: section.lines)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guide-part-\(section.id)")
    }

    private func picture(_ name: String) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button { open(section) } label: {
                GuidePicture(name: name, marks: section.marks)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Picture of \(section.title). Tap to see it bigger")
            .accessibilityIdentifier("guidePicture-\(name)")
            // The screen itself says what a tap does: a small capsule under the picture, on its right.
            Button { open(section) } label: {
                Text("Tap to see it bigger")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(section.hue)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(section.hue.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// A part on its own: on iPhone a sheet, on iPad and Mac the whole screen (a sheet there is no bigger than the guide).
/// The picture as wide as there is room for (up to 1.5 times the real screen), pinch or double-tap to go closer,
/// its circles, and its lines under it — or beside it when a phone picture leaves room. Done (Escape with a keyboard).
struct GuideViewerView: View {
    let section: GuideSection
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let room = geo.size.width - 32
                let natural = section.picture.flatMap(GuideImages.size) ?? CGSize(width: 390, height: 400)
                // A phone picture on a wide screen: lines beside it, the picture as tall as the screen allows.
                let beside = natural.width < 600 && room >= natural.width + 340
                let fit = beside
                    ? min(natural.width * 1.5, room - 340, max(geo.size.height - 80, 300) * natural.width / natural.height)
                    : min(natural.width * 1.5, room)
                ScrollView(.vertical) {
                    Group {
                        if beside {
                            HStack(alignment: .top, spacing: 24) {
                                picture(fit: fit, room: room - 340)
                                GuideLines(lines: section.lines).frame(maxWidth: 460, alignment: .leading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                picture(fit: fit, room: room)
                                GuideLines(lines: section.lines)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("guideViewer")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("guideViewerDone")
                }
            }
        }
    }

    @ViewBuilder private func picture(fit: CGFloat, room: CGFloat) -> some View {
        if let name = section.picture {
            let width = fit * min(max(zoom * pinch, 1), 3)
            VStack(alignment: .trailing, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: width > room + 1) {
                    GuidePicture(name: name, marks: section.marks, most: 10)
                        .frame(width: width)
                }
                .frame(width: min(width, room))
                .scrollDisabled(width <= room + 1)
                .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 3) })
                .onTapGesture(count: 2) { withAnimation(.easeInOut(duration: 0.2)) { zoom = zoom > 1.05 ? 1 : 2 } }
                .accessibilityIdentifier("guideViewerPicture")
                Text(zoom > 1.05 ? "Double-tap to go back" : "Pinch or double-tap to go closer")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}
