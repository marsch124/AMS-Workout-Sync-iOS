import SwiftUI
import UniformTypeIdentifiers
import WorkoutCore

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var picking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)

                    DropboxSection()

                    SectionHeading(text: "Workbook")
                    Group {
                        row(store.fileName.isEmpty ? "No workbook yet" : store.fileName,
                            sub: readLine)
                        HStack(spacing: 10) {
                            Button("Choose in Files") { picking = true }
                                .buttonStyle(.borderedProminent).tint(Theme.today)
                            Button("Read again") { store.refresh() }
                                .buttonStyle(.bordered).tint(Theme.today)
                                .disabled(!store.hasWorkbook)
                        }
                        if let problem = store.lastProblem {
                            Text(problem).font(.footnote).foregroundStyle(Theme.danger)
                        }
                    }

                    if let mapping = store.mapping {
                        SectionHeading(text: "How the sheet is read")
                        row(mapping.sheets.joined(separator: ", "),
                            sub: "\(store.plan.count) sessions · headings on row \(mapping.headerRow)")
                        row("Durations in \(mapping.units.duration), distances in \(mapping.units.distance)",
                            sub: "Done is written \(mapping.doneValue), missed \(mapping.missedValue)")
                    }

                    SectionHeading(text: "This app")
                    row("iPhone preview \(version)",
                        sub: "Reads your plan and never changes it. Logging stays in the web app for now.")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .workbookPicker(isPresented: $picking)
    }

    private var readLine: String {
        guard let at = store.readAt else { return "Pick your plan in Files → Dropbox" }
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

    private func row(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            Text(sub).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
