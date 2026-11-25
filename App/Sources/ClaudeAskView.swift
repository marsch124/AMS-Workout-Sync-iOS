import SwiftUI
import WorkoutCore

/* The last five questions in memory only (pictures, with the fake switch). */
private final class AskMemoryStore: ClaudeAskStoring {
    var items: [ClaudeAskItem]
    init(_ items: [ClaudeAskItem]) { self.items = items }
    func load() -> [ClaudeAskItem] { items }
    func save(_ items: [ClaudeAskItem]) { self.items = items }
}

@MainActor
final class ClaudeAskModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var items: [ClaudeAskItem]
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let storing: ClaudeAskStoring

    init() {
        if ClaudeDebug.ask != nil {
            let seed = ClaudeDebug.ask == "empty" ? [] : [ClaudeAskItem(at: Date(), question: ClaudeAsk.inventedQuestion, answer: ClaudeAsk.inventedAnswer)]
            storing = AskMemoryStore(seed)
        } else {
            storing = UserDefaultsAskStore()
        }
        items = storing.load()
    }

    var canAsk: Bool { !busy && ClaudeAsk.cleanQuestion(text) != nil }

    func clear() {
        items = []
        storing.save([])
        message = nil
    }

    private func keep(_ item: ClaudeAskItem) {
        items = items.adding(item)
        storing.save(items)
    }

    func ask(book: PlanBook?, today: String) async {
        guard !busy, let question = ClaudeAsk.cleanQuestion(text) else { return }
        message = nil
        // Illness and pain are never put to Claude: the app answers with one fixed line, nothing is sent.
        if ClaudeAsk.isAboutIllness(question) {
            keep(ClaudeAskItem(at: Date(), question: question, answer: ClaudeAsk.doctorLine, local: true))
            text = ""
            return
        }
        guard let book else {
            if !ClaudeKey.isFake { message = "The plan is not in the app yet, so there is nothing to ask about."; return }
            await send(question, plan: ClaudeAskPlan(today: today, phase: "", days: [], zoneNames: []))
            return
        }
        await send(question, plan: ClaudeAsk.plan(book: book, today: today))
    }

    private func send(_ question: String, plan: ClaudeAskPlan) async {
        let client = ClaudeClient.shared
        let request = ClaudeAsk.request(question: question, plan: plan)
        busy = true
        let result = await client.run(kind: "ask", label: "Answered a question", detail: String(question.prefix(80)),
                                      body: ClaudeAsk.body(system: request.system, user: request.user),
                                      fake: ClaudeAsk.inventedAnswer, read: { ClaudeAsk.read($0) })
        busy = false
        switch result {
        case .answer(let answer):
            keep(ClaudeAskItem(at: Date(), question: question, answer: answer))
            text = ""
        case .notPassed:
            message = ClaudeAsk.didNotPass
        case .none:
            message = client.trouble == nil ? ClaudeAsk.nothingCame : nil
        }
    }
}

extension Theme {
    /* The page behind the Ask page: the plan's blue, very light. */
    static let askGround = Color.dynamic(light: 0xEEF4FC, dark: 0x0F1B2B)
}

/* The small button on the Plan and Sessions pages. Invisible while Claude is off; the calm line while it is refused. */
struct ClaudeAskButton: View {
    @ObservedObject private var client = ClaudeClient.shared
    @State private var showing = false
    var inset: CGFloat = 0

    var body: some View {
        if client.canWrite {
            if let trouble = client.trouble {
                Text(trouble.restLine).font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset)
                    .accessibilityIdentifier("claude-ask-trouble")
            } else {
                HStack {
                    Button("Ask about your plan") { showing = true }
                        .settingsButton(tint: Theme.plan)
                        .accessibilityIdentifier("claude-ask-open")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, inset)
                .sheet(isPresented: $showing) { NavigationStack { ClaudeAskView(inSheet: true) } }
            }
        }
    }
}

/* Settings → Claude: the same page, pushed. */
struct ClaudeAskEntry: View {
    @ObservedObject private var client = ClaudeClient.shared
    var body: some View {
        if client.canWrite, client.trouble == nil {
            NavigationLink { ClaudeAskView() } label: {
                SettingsRow(title: "Ask about your plan", sub: "Claude explains the plan and the rule book; it changes nothing", chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("claude-ask-row")
        }
    }
}

struct ClaudeAskView: View {
    var inSheet = false
    @EnvironmentObject var store: Store
    @ObservedObject private var client = ClaudeClient.shared
    @StateObject private var model = ClaudeAskModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                head
                Text(ClaudeAsk.sentWords + " " + ClaudeAsk.costWords)
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .accessibilityIdentifier("claude-ask-sent")
                if let trouble = client.trouble {
                    Text(trouble.restLine).font(.footnote).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-ask-trouble")
                } else {
                    asking
                }
                history
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.askGround.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Ask about your plan").font(.headline).foregroundStyle(Theme.text)
            }
            if inSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("claude-ask-done")
                }
            }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ASK ABOUT YOUR PLAN").font(.caption.weight(.bold)).tracking(1).opacity(0.85)
            Text("Claude explains the plan and the rule book. It never changes anything; to change something you use Move, Change or the suggestion card.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.plan))
    }

    @ViewBuilder private var asking: some View {
        TextField("Why is Thursday\u{2019}s ride only 45 minutes?", text: $model.text, axis: .vertical)
            .lineLimit(2...4)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
            .accessibilityIdentifier("claude-ask-field")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(ClaudeAsk.examples.enumerated()), id: \.offset) { i, example in
                Button { model.text = example } label: {
                    Text(example).font(.footnote).foregroundStyle(Theme.plan)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.surface))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("claude-ask-example-\(i + 1)")
            }
        }
        Button {
            Task { await model.ask(book: store.book, today: store.today) }
        } label: {
            Text(model.busy ? "Asking\u{2026}" : "Ask").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(Theme.mainButton)
        .disabled(!model.canAsk)
        .accessibilityIdentifier("claude-ask-send")
        if let message = model.message {
            Text(message).font(.footnote).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-ask-message")
        }
    }

    @ViewBuilder private var history: some View {
        if !model.items.isEmpty {
            SectionHeading(text: "Your last questions")
            ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOU ASKED").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.plan)
                    Text(item.question).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(item.answer).font(.subheadline).foregroundStyle(Theme.text)
                        .accessibilityIdentifier(i == 0 ? "claude-ask-answer" : "claude-ask-answer-\(i + 1)")
                    if item.local {
                        Text("Answered by the app. Nothing was sent.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            }
            Button("Clear") { model.clear() }
                .settingsButton(tint: Theme.danger)
                .accessibilityIdentifier("claude-ask-clear")
        }
    }
}
