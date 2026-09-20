import SwiftUI
import WorkoutCore

/*
 * What Z2 means for him: the zones sheet, read, never recalculated. The
 * whole sheet lives under Settings → Your zones; a session's intensity pill
 * opens just the rows it names.
 */
struct ZonesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let z = store.zones {
                    let known = z.current.filter { !$0.value.isEmpty }
                    SectionHeading(text: "In use")
                    if known.isEmpty {
                        Card { Text("No test result is entered in the sheet yet.").font(.body).foregroundStyle(Theme.secondary) }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(known, id: \.label) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                                    Text(row.label).font(.caption).foregroundStyle(Theme.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                            }
                        }
                    }
                    if !z.latestTest.isEmpty {
                        Text("From " + z.latestTest).font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    if z.waitingForExcel { WaitingForExcel() }
                    ForEach(z.tables, id: \.title) { table in ZoneTableCard(table: table, waiting: z.waitingForExcel) }
                    if !z.note.isEmpty {
                        Card { Text(z.note).font(.footnote).foregroundStyle(Theme.secondary) }
                    }
                    if !z.abbreviations.isEmpty {
                        SectionHeading(text: "The words")
                        ForEach(z.abbreviations, id: \.label) { row in
                            Card {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.label).font(.headline).foregroundStyle(Theme.text)
                                    Text(row.value).font(.footnote).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }
                    Text("Read from the sheet " + z.sheet + " in your workbook. The app never works a zone out itself.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                } else {
                    Card {
                        Text("Your workbook has no Test Results & Zones sheet, or it could not be read. The zones come from that sheet; the app never works them out itself.")
                            .font(.body).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .padding(16).padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Your zones")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/* Said in full once, so the app never claims nothing was entered when it was. */
struct WaitingForExcel: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your zone tables are empty").font(.headline).foregroundStyle(Theme.text)
                Text("The sheet works the zones out with formulas, and the numbers Excel had worked out are not in the file any more — another program saved it without them. Your test results themselves are still there. Open the plan in Excel on the Mac once and save it, and the tables fill in again.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityIdentifier("zones-waiting-for-excel")
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}

struct ZoneTableCard: View {
    let table: ZoneTable
    /* Empty because Excel has not worked them out, not because nothing was entered. */
    var waiting = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(table.title).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.secondary)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).font(.body).foregroundStyle(Theme.text)
                        Spacer(minLength: 12)
                        if row.value.isEmpty {
                            Text(waiting ? "—" : "not entered yet").font(.footnote).foregroundStyle(Theme.secondary)
                        } else {
                            Text(row.value).font(.body.weight(.bold).monospacedDigit()).foregroundStyle(Theme.text)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("zone-row")
                }
            }
        }
    }
}

/* The pill on a session, tinted like its sport so it reads as something to tap. */
struct ZonePill: View {
    let text: String
    let sport: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Text("›").font(.footnote.weight(.bold))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.sportInk(sport))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Theme.sport(sport).opacity(0.22)))
    }
}

struct ZoneAsk: Identifiable {
    let id = UUID()
    let intensity: String
    let sport: String
}

struct ZoneSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let ask: ZoneAsk

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ask.intensity).font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
                        .accessibilityIdentifier("zone-sheet-title")
                    if let z = store.zones {
                        let tables = z.explain(intensity: ask.intensity, sport: ask.sport)
                        let wantsRpe = ask.intensity.uppercased().contains("RPE")
                        if !z.latestTest.isEmpty {
                            Text("For you, from " + z.latestTest).font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        ForEach(tables, id: \.title) { table in ZoneTableCard(table: table) }
                        if wantsRpe, let rpe = z.rpe {
                            Card {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("RPE").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(Theme.secondary)
                                    Text(rpe).font(.body).foregroundStyle(Theme.text)
                                }
                            }
                        }
                        if (ask.sport == "bike" || ask.sport == "brick"), !Zones.zones(in: ask.intensity).isEmpty,
                           !tables.contains(where: { $0.kind == .bike }) {
                            Text("No bike FTP is entered in the sheet yet, so there are no power zones — heart rate only.")
                                .font(.footnote).foregroundStyle(Theme.secondary)
                        }
                        if z.waitingForExcel {
                            WaitingForExcel()
                        } else if tables.isEmpty, !(wantsRpe && z.rpe != nil) {
                            Card { Text("Nothing in your zones sheet matches " + ask.intensity + ".").font(.body).foregroundStyle(Theme.secondary) }
                        }
                        NavigationLink { ZonesView() } label: {
                            Text("All your zones ›").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.today)
                    } else {
                        Card { Text("Your workbook has no Test Results & Zones sheet, so the app cannot say what this means.").font(.body).foregroundStyle(Theme.secondary) }
                    }
                }
                .padding(16).padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
