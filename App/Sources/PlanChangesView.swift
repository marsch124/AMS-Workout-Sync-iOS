import SwiftUI
import WorkoutCore

/*
 * Settings → Changes to the plan: every change made to the plan itself, newest
 * first — what was there before, what is there now — each with a way back.
 */
struct PlanChangesView: View {
    @EnvironmentObject var store: Store
    @State private var undoing: PlanChange?

    var body: some View {
        ScrollView {
            let changes = store.planChanges
            VStack(alignment: .leading, spacing: 8) {
                if changes.isEmpty {
                    Text("No changes yet. Open a session and tap Change.")
                        .font(.callout).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("changes-empty")
                }
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    if let batch = MobilityStrength.batch(of: change.why) {
                        // One round of Mobility and strength = one entry, shown at its newest change.
                        if changes.firstIndex(where: { MobilityStrength.batch(of: $0.why) == batch }) == index {
                            MobilityStrengthChangeRow(changes: changes.filter { MobilityStrength.batch(of: $0.why) == batch },
                                                      batch: batch, index: index)
                        }
                    } else if let mark = PlanMakerBatch.of(change.why) {
                        if changes.firstIndex(where: { PlanMakerBatch.of($0.why) == mark }) == index {
                            PlanMakerChangeRow(changes: changes.filter { PlanMakerBatch.of($0.why) == mark }, index: index)
                        }
                    } else if let batch = RepeatRule.batch(of: change.why) {
                        // One repeat = one entry, shown at its newest session.
                        if changes.firstIndex(where: { RepeatRule.batch(of: $0.why) == batch }) == index {
                            RepeatChangeRow(changes: changes.filter { RepeatRule.batch(of: $0.why) == batch }, index: index)
                        }
                    } else {
                        row(change, index)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Changes to the plan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Undo this change?", isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } }), titleVisibility: .visible) {
            Button("Undo", role: undoing?.kind == "add" ? .destructive : nil) {
                if let c = undoing { store.undoChange(c.id) }
                undoing = nil
            }
            Button("Keep it", role: .cancel) { undoing = nil }
        } message: {
            if undoing?.kind == "add" { Text("The session is taken out of the plan again.") }
        }
    }

    private func kindWord(_ kind: String) -> String {
        switch kind {
        case "add": return "Added"
        case "remove": return "Taken out"
        default: return "Changed"
        }
    }

    private func row(_ c: PlanChange, _ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(kindWord(c.kind).uppercased()).font(.caption.weight(.bold)).tracking(0.6)
                    .foregroundStyle(c.kind == "remove" ? Theme.danger : Theme.plan)
                Text(c.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if c.undone {
                    Text("Undone").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-undone-\(index)")
                } else if store.canUndo(c.id) {
                    Button("Undo") { undoing = c }
                        .settingsButton(tint: c.kind == "add" ? Theme.danger : Theme.today)
                        .accessibilityIdentifier("change-undo-\(index)")
                } else {
                    // Only the newest change to a session can be undone; an
                    // older one would quietly take the later ones with it.
                    Text("Changed again since").font(.caption).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-older-\(index)")
                }
            }
            Text(c.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            if !c.why.isEmpty {
                Text(c.why).font(.footnote).foregroundStyle(Theme.secondary)
            }
            if !c.before.isEmpty {
                Text("Before: " + c.before).font(.footnote).foregroundStyle(Theme.secondary)
            }
            if !c.after.isEmpty {
                Text("Now: " + c.after).font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .opacity(c.undone ? 0.7 : 1)
    }
}
