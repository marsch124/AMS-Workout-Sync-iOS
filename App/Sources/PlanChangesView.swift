import SwiftUI
import WorkoutCore

/*
 * Settings → Changes to the plan: every change made to the plan itself, newest
 * first — what was there before, what is there now — each with a way back.
 */
struct PlanChangesView: View {
    @EnvironmentObject var store: Store

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
                    row(change, index)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Changes to the plan")
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("Taken back").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .accessibilityIdentifier("change-undone-\(index)")
                } else {
                    Button("Take back") { store.undoChange(c.id) }
                        .settingsButton(tint: Theme.today)
                        .accessibilityIdentifier("change-undo-\(index)")
                }
            }
            Text(c.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
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
