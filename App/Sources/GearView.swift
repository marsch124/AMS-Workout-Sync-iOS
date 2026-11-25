import SwiftUI
import WorkoutCore

/*
 * Settings → Shoes and bikes (round 28, pick 37). His gear as tiles under a
 * head card in Settings' slate. Kilometres = the figure it already had + the
 * logged distance of every done session of its sport on the days it was the one
 * in use. A session with no distance logged counts nothing, and the tile says
 * how many were left out. Shown only: nothing here changes the plan. Each item
 * is one key on the shelf (gear/<id>), so it follows him between his devices.
 */
enum GearLook {
    static let fill = Color.dynamic(light: 0x5A6B7B, dark: 0x4A5A6A)
    static let tile = Color.dynamic(light: 0xE8EDF2, dark: 0x25313D)
    static let ground = Color.dynamic(light: 0xF3F6F9, dark: 0x141A21)
    static let ink = Color.dynamic(light: 0x455565, dark: 0xB4C2D0)
}

extension Store {
    /* Every done session with the distance it logged, in kilometres (nil when none). */
    var gearSessions: [GearSession] {
        guard let mapping else { return [] }
        return displayed
            .filter { $0.discipline.id != "rest" && $0.logged && !$0.missed }
            .map { w in
                let a = Stats.actualsOf(w, mapping)
                return GearSession(day: w.dayKey, sport: w.discipline.id, km: a.km > 0 ? a.km : nil)
            }
    }
}

struct GearPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var shelf = ShelfStore.shared
    @State private var editing: GearItem?
    @State private var adding = false

    private var items: [GearItem] {
        shelf.keys(prefix: "gear/").compactMap { shelf.value(GearItem.self, for: $0) }
            .sorted { ($0.inUse ? 0 : 1, $0.name.lowercased()) < ($1.inUse ? 0 : 1, $1.name.lowercased()) }
    }

    var body: some View {
        let all = items
        let active = all.filter { !$0.retired }
        let retired = all.filter(\.retired)
        let sessions = store.gearSessions
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head(active, retired)
                if active.isEmpty {
                    Text("Add your shoes and bikes. The kilometres are counted from the sessions you log.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { n, item in
                        tile(item, n, sessions)
                    }
                }
                Button { adding = true } label: {
                    Text("Add shoes or a bike").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(Capsule().fill(GearLook.fill))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gear-add")
                if !retired.isEmpty {
                    Text("RETIRED").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.secondary).padding(.top, 8)
                    ForEach(Array(retired.enumerated()), id: \.element.id) { n, item in
                        retiredRow(item, n, sessions)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gear-page")
        .background(GearLook.ground.ignoresSafeArea())
        .navigationTitle("Shoes and bikes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { GearEditView(item: nil, all: all, sessions: sessions, today: store.today) }
        .sheet(item: $editing) { GearEditView(item: $0, all: all, sessions: sessions, today: store.today) }
        .tint(GearLook.fill)
        #if DEBUG
        .task { seedForPicture() }
        #endif
    }

    // MARK: head card

    private func head(_ active: [GearItem], _ retired: [GearItem]) -> some View {
        let inUse = active.filter(\.inUse).count
        return VStack(alignment: .leading, spacing: 2) {
            Text("SHOES AND BIKES").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(inUse)").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Text("in use").font(.headline).foregroundStyle(.white.opacity(0.9))
            }
            if active.count > inUse || !retired.isEmpty {
                Text([active.count > inUse ? "\(active.count - inUse) put aside" : nil,
                      retired.isEmpty ? nil : "\(retired.count) retired"].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GearLook.fill))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gear-head")
    }

    // MARK: a tile

    private func km(_ v: Double) -> String { PlanNumbers.figure(v) }

    private func tile(_ item: GearItem, _ n: Int, _ sessions: [GearSession]) -> some View {
        let c = item.count(sessions)
        return VStack(alignment: .leading, spacing: 5) {
            Text(item.kind.word.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(GearLook.ink)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                Text("\u{00B7} \(km(c.km)) km").font(.headline).foregroundStyle(Theme.text)
            }
            Text(item.inUse ? "In use since " + (item.since.map(Dates.short) ?? "") : "Put aside")
                .font(.footnote).foregroundStyle(Theme.secondary)
            Text(item.countWords(c)).font(.footnote).foregroundStyle(Theme.secondary)
            if let limit = item.limitKm { limitBar(c.km, limit) }
            HStack(spacing: 14) {
                if item.kind != .other {
                    if item.inUse {
                        smallButton("Put aside", id: "gear-aside-\(n)") { change(GearSet.putAside(item.id, on: store.today, in: items)) }
                    } else {
                        smallButton("Use from today", id: "gear-use-\(n)") { change(GearSet.using(item.id, from: store.today, in: items)) }
                    }
                }
                smallButton("Change", id: "gear-edit-\(n)") { editing = item }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GearLook.tile))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gear-tile-\(n)")
    }

    /* Kilometres so far against the limit he set. The part still ahead is an OUTLINED track (pale would mean "still to do"). */
    @ViewBuilder
    private func limitBar(_ now: Double, _ limit: Double) -> some View {
        if now > limit {
            Text("Past the \(km(limit)) km you set.").font(.footnote).foregroundStyle(Theme.secondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().stroke(GearLook.ink.opacity(0.7), lineWidth: 1.2)
                        Capsule().fill(GearLook.fill)
                            .frame(width: max(8, geo.size.width * min(1, now / limit)))
                    }
                }
                .frame(height: 8)
                Text("\(km(now)) of \(km(limit)) km").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
            }
        }
    }

    private func retiredRow(_ item: GearItem, _ n: Int, _ sessions: [GearSession]) -> some View {
        let c = item.count(sessions)
        return Button { editing = item } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("\u{00B7} \(km(c.km)) km").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                }
                Text(item.kind.word + (item.periods.last?.until.map { " · retired " + Dates.short($0) } ?? ""))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(GearLook.tile))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gear-retired-\(n)")
    }

    private func smallButton(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(GearLook.ink)
            .frame(minHeight: 30)
            .accessibilityIdentifier(id)
    }

    /* Writes only the items that changed, one key each. */
    private func change(_ new: [GearItem]) {
        let old = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for i in new where old[i.id] != i { shelf.set(i, for: "gear/" + i.id) }
    }

    #if DEBUG
    /* For a picture: two shoes and a bike, invented, when the shelf holds none. */
    private func seedForPicture() {
        guard ProcessInfo.processInfo.environment["AMSWS_GEAR_PAGE"] != nil, shelf.keys(prefix: "gear/").isEmpty else { return }
        let t = store.today
        var blue = GearItem(id: "g-blue", name: "Blue runners", kind: .shoes, since: PlanView.addDays(t, -70), startKm: 180, limitKm: 700)
        var grey = GearItem(id: "g-grey", name: "Grey trainers", kind: .shoes, since: PlanView.addDays(t, -300), startKm: 690, limitKm: 700)
        grey.periods = [GearPeriod(from: PlanView.addDays(t, -300), until: PlanView.addDays(t, -70))]
        let road = GearItem(id: "g-road", name: "Road bike", kind: .bike, since: PlanView.addDays(t, -200), startKm: 1200, limitKm: 4000)
        blue.limitKm = 700
        for i in [blue, grey, road] { shelf.set(i, for: "gear/" + i.id) }
    }
    #endif
}

// MARK: - add or change

struct GearEditView: View {
    let item: GearItem?
    let all: [GearItem]
    let sessions: [GearSession]
    let today: String
    @ObservedObject private var shelf = ShelfStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind = GearKind.shoes
    @State private var since = Date()
    @State private var startKm = ""
    @State private var limit = ""
    @State private var useNow = true
    @State private var loaded = false
    @State private var failed = false
    @State private var askRemove = false
    @State private var askRetire = false

    private var number: (String) -> Double? { { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func dayKey(_ d: Date) -> String {
        // The picker works in the phone's calendar; the day he sees is the day kept.
        let l = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", l.year ?? 1970, l.month ?? 1, l.day ?? 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    labelled("Name") {
                        TextField("e.g. Blue runners", text: $name).textFieldStyle(.plain).padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                            .accessibilityIdentifier("gear-name")
                    }
                    labelled("Kind") {
                        Picker("Kind", selection: $kind) {
                            ForEach(GearKind.allCases, id: \.self) { Text($0.word).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("gear-kind")
                    }
                    if item == nil {
                        Toggle("In use now", isOn: $useNow).accessibilityIdentifier("gear-use-now")
                            .tint(GearLook.fill)
                    }
                    if item == nil ? useNow : (item?.periods.isEmpty == false) {
                        labelled("In use since") {
                            DatePicker("In use since", selection: $since, displayedComponents: .date)
                                .labelsHidden().accessibilityIdentifier("gear-since")
                        }
                    }
                    labelled("Kilometres it already had") {
                        TextField("0", text: $startKm).keyboardType(.decimalPad).textFieldStyle(.plain).padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                            .accessibilityIdentifier("gear-start-km")
                    }
                    labelled("Look at it again at … km (optional)") {
                        TextField("e.g. 700", text: $limit).keyboardType(.decimalPad).textFieldStyle(.plain).padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                            .accessibilityIdentifier("gear-limit")
                    }
                    if kind == .other {
                        Text("Other counts no sessions by itself: only the kilometres you give it.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if failed { Text("Not saved. Try again.").font(.footnote).foregroundStyle(Theme.secondary) }
                    if let item, !item.retired {
                        HStack(spacing: 16) {
                            Button("Retire") { askRetire = true }.accessibilityIdentifier("gear-retire")
                            Button("Remove") { askRemove = true }.accessibilityIdentifier("gear-remove")
                        }
                        .font(.subheadline.weight(.semibold)).buttonStyle(.plain).foregroundStyle(GearLook.ink)
                        .padding(.top, 6)
                    } else if item != nil {
                        Button("Remove") { askRemove = true }.accessibilityIdentifier("gear-remove")
                            .font(.subheadline.weight(.semibold)).buttonStyle(.plain).foregroundStyle(GearLook.ink)
                    }
                }
                .padding(14)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(GearLook.ground.ignoresSafeArea())
            .navigationTitle(item == nil ? "New" : "Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("gear-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if save() { dismiss() } else { failed = true } }
                        .disabled(!canSave).accessibilityIdentifier("gear-save")
                }
            }
            .confirmationDialog("Remove \(item?.name ?? "this")? It is taken off all your devices and cannot be brought back.",
                                isPresented: $askRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let item { shelf.remove(for: "gear/" + item.id) }
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            }
            .confirmationDialog("Retire \(item?.name ?? "this")? It moves to Retired with its final figure.",
                                isPresented: $askRetire, titleVisibility: .visible) {
                Button("Retire") {
                    if let item {
                        for i in GearSet.retired(item.id, on: today, in: all, sessions: sessions) where i.id == item.id {
                            shelf.set(i, for: "gear/" + i.id)
                        }
                    }
                    dismiss()
                }
                Button("Keep using it", role: .cancel) {}
            }
        }
        .tint(GearLook.fill)
        .onAppear(perform: load)
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(GearLook.ink)
            content()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let item else {
            if let d = parseDayKey(today) { since = Self.local(d) }
            return
        }
        name = item.name; kind = item.kind
        startKm = item.startKm > 0 ? PlanNumbers.figure(item.startKm).replacingOccurrences(of: ",", with: "") : ""
        limit = item.limitKm.map { PlanNumbers.figure($0).replacingOccurrences(of: ",", with: "") } ?? ""
        if let f = item.periods.last?.from, let d = parseDayKey(f) { since = Self.local(d) }
    }

    /* A day key as a date in the phone's calendar at noon, so the picker shows the same day. */
    private static func local(_ d: Date) -> Date {
        let c = utc.dateComponents([.year, .month, .day], from: d)
        var l = DateComponents(); l.year = c.year; l.month = c.month; l.day = c.day; l.hour = 12
        return Calendar.current.date(from: l) ?? d
    }

    private func save() -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let start = max(0, number(startKm) ?? 0)
        let lim = number(limit).flatMap { $0 > 0 ? $0 : nil }
        let day = dayKey(since)
        if var old = item {
            old.name = trimmed; old.kind = kind; old.startKm = start; old.limitKm = lim
            if !old.periods.isEmpty { old.periods[old.periods.count - 1].from = day }
            return shelf.set(old, for: "gear/" + old.id)
        }
        let new = GearItem(name: trimmed, kind: kind, startKm: start, limitKm: lim)
        var list = all + [new]
        if useNow { list = GearSet.using(new.id, from: day, in: list) }
        let before = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var ok = true
        for i in list where before[i.id] != i { ok = shelf.set(i, for: "gear/" + i.id) && ok }
        return ok
    }
}
