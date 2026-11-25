import SwiftUI
import WorkoutCore

/*
 * Settings → Move the plan into this app. The workbook is taken in and counted
 * against what the app made of it; he looks at both sides; only his tap on the
 * switch moves the plan in. Until then nothing is saved, and the Excel file is
 * never touched.
 */
struct MoveInView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var switched = false
    @State private var fromICloud = false
    @State private var usingICloud = false
    @State private var cloudProblem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if switched {
                    finished
                } else if store.cloud.cloudHasPlan, store.incoming == nil {
                    // A plan is already in iCloud, moved in on another device: a second import of the
                    // Excel file would make two plans. This iPhone takes the one in iCloud instead.
                    useICloud
                } else {
                    intro
                    if let taken = store.incoming {
                        proof(taken)
                    } else {
                        Button { store.takePlanIn() } label: {
                            Text(store.takingIn ? "Counting…" : "Take the plan in and count")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.mainButton)
                        .accessibilityIdentifier("movein-take")
                    }
                    if let why = store.homeProblem {
                        Text(why).font(.footnote).foregroundStyle(Theme.danger)
                            .accessibilityIdentifier("movein-problem")
                    }
                    if store.incoming == nil {
                        Button("Cancel") { store.cancelTakingIn(); dismiss() }
                            .settingsButton(tint: Theme.secondary)
                            .accessibilityIdentifier("movein-cancel")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        // The small centred title every other Settings page has; Cancel stays at the top left.
        .navigationTitle("The plan moves in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("The plan moves in").font(.headline).foregroundStyle(Theme.text)
                    .accessibilityIdentifier("movein-title")
            }
            if !switched {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.cancelTakingIn(); dismiss() }
                        .foregroundStyle(Theme.today)
                        .accessibilityIdentifier("movein-cancel-top")
                }
            }
        }
        .interactiveDismissDisabled(store.incoming != nil && !switched)
        // The switch reads the Excel file once more before it happens, so the
        // page waits to be told rather than assuming.
        .onChange(of: store.planLivesHere) { _, lives in if lives { switched = true } }
        #if DEBUG
        .onAppear {
            guard ProcessInfo.processInfo.environment["AMSWS_MOVEIN"] != nil, store.incoming == nil, !store.planLivesHere else { return }
            store.takePlanIn()
        }
        .onChange(of: store.incoming == nil) { _, none in
            guard !none, ProcessInfo.processInfo.environment["AMSWS_MOVEIN"] == "done" else { return }
            store.makeAppTheHome()
            switched = store.planLivesHere
        }
        #endif
    }

    private var useICloud: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your plan is already in iCloud — it was moved into the app on another device. Use it here, and this iPhone shows the same plan as your other devices.")
            Text("Anything still waiting on this iPhone is written into it. Your Excel file is not changed.")
            Button {
                guard !usingICloud else { return }
                usingICloud = true
                cloudProblem = nil
                Task {
                    cloudProblem = await store.cloud.useCloudPlanHere()
                    usingICloud = false
                    if cloudProblem == nil { fromICloud = true; switched = true }
                }
            } label: {
                Text(usingICloud ? "Bringing the plan from iCloud…" : "Use the plan from iCloud")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(Theme.mainButton)
            .accessibilityIdentifier("movein-use-icloud")
            if let cloudProblem {
                Text(cloudProblem).font(.footnote).foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("movein-problem")
            }
            Button("Cancel") { dismiss() }
                .settingsButton(tint: Theme.secondary)
                .accessibilityIdentifier("movein-cancel")
        }
        .font(.subheadline).foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now the plan lives in the Excel file in Dropbox. Here it moves into this app.")
            Text("1 · The app takes in the Excel file and counts both sides.")
            Text("2 · You look at the counts.")
            Text("3 · You tap Make this app the plan’s home. Until then nothing is saved.")
        }
        .font(.subheadline).foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func proof(_ taken: PlanImport) -> some View {
        let proof = taken.proof
        SectionHeading(text: "Excel and the app, side by side")
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text("Excel").frame(width: 46, alignment: .trailing)
                Text("App").frame(width: 46, alignment: .trailing)
                Color.clear.frame(width: 52, height: 1)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            .accessibilityHidden(true)
            ForEach(Array(proof.lines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 6) {
                    Text(line.label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(line.before).frame(width: 46, alignment: .trailing)
                    Text(line.after).frame(width: 46, alignment: .trailing)
                    mark(same: line.same).frame(width: 52, alignment: .leading)
                }
                .font(.footnote).monospacedDigit().foregroundStyle(Theme.secondary)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("proof-row-\(index)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))

        VStack(alignment: .leading, spacing: 4) {
            if proof.matches {
                Text("Everything matches.").font(.headline).foregroundStyle(Theme.today)
            } else {
                Text("Something differs — nothing was changed.").font(.headline).foregroundStyle(Theme.danger)
                ForEach(Array(proof.differences.prefix(10).enumerated()), id: \.offset) { _, words in
                    Text(words).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Text("Correct it in the Excel file, then start again.").font(.footnote).foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proof-verdict")

        if !proof.after.months.isEmpty {
            SectionHeading(text: "Month by month")
            VStack(spacing: 0) {
                ForEach(Array(proof.after.months.enumerated()), id: \.offset) { index, m in
                    let same = proof.before.months.first { $0.month == m.month } == m
                    HStack(spacing: 8) {
                        Text("\(m.label) · \(m.sessions) sessions · \(m.done) done · \(m.missed) missed · \(m.plannedMinutes) planned min · \(m.recordedMinutes) recorded min")
                            .font(.footnote).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        mark(same: same)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("proof-month-\(index)")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }

        if !taken.oddities.isEmpty {
            SectionHeading(text: "Looked odd in the file")
            ForEach(Array(taken.oddities.enumerated()), id: \.offset) { index, odd in
                Text(odd.words).font(.footnote).foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                    .accessibilityIdentifier("proof-odd-\(index)")
            }
            Text("Taken in as written. Correct them later with the pen.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }

        if proof.matches {
            Button {
                store.makeAppTheHome()
            } label: {
                Text(store.switching ? "Reading the Excel file once more…" : "Make this app the plan’s home")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(Theme.mainButton)
            .accessibilityIdentifier("movein-switch")
            .padding(.top, 6)
            Text("Your Excel file is not changed. You can go back for three weeks.")
                .font(.caption).foregroundStyle(Theme.secondary)
            if let why = store.homeProblem {
                Text(why).font(.footnote).foregroundStyle(Theme.danger).accessibilityIdentifier("movein-switch-problem")
            }
        }
        Button("Cancel") { store.cancelTakingIn(); dismiss() }
            .settingsButton(tint: Theme.secondary)
            .accessibilityIdentifier("movein-cancel")
    }

    /* Said in words, both ways: the tick means done in this app and nothing else. */
    @ViewBuilder
    private func mark(same: Bool) -> some View {
        if same {
            Text("same").font(.caption.weight(.bold)).foregroundStyle(Theme.today)
        } else {
            Text("differs").font(.caption.weight(.bold)).foregroundStyle(Theme.danger)
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Done. The plan lives in this app now.").font(.headline).foregroundStyle(Theme.today)
                .accessibilityIdentifier("movein-finished")
            Text("Logging, moving and changing sessions now happen here. Nothing is written into your Excel file any more.")
            if fromICloud {
                Text("It is the same plan as on your other devices. Your Excel file stays in Dropbox, untouched.")
            } else {
                Text("Your Excel file stays in Dropbox, untouched. For three weeks Settings › Go back to Excel can return to it.")
            }
            Button { dismiss() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(Theme.mainButton)
            .accessibilityIdentifier("movein-done")
        }
        .font(.subheadline).foregroundStyle(Theme.secondary)
    }
}
