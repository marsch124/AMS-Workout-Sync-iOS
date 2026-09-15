import SwiftUI

/*
 * "How this works" and "What's new" — the same two screens every AMS app
 * carries, written for the person using it. Kept in one place so a release
 * that changes behaviour changes the words beside it.
 */
struct GuideView: View {
    struct Part: Identifiable {
        let id: String
        let body: [String]
    }

    static let parts: [Part] = [
        Part(id: "What this app is", body: [
            "Your training plan lives in an Excel workbook in Dropbox. This app reads it, shows you the week and the day, and writes what you did back into the cells that are already there — the same cells, the same way, as the web app.",
            "It writes nothing anywhere else. Every other part of the workbook is copied through untouched."
        ]),
        Part(id: "Today", body: [
            "The week strip is one column a day, one bar a session. Solid is recorded, hollow is still to do, hatched is marked missed, dotted is an extra outside the plan. The rest day is a flat line. Tap the card for the key.",
            "Below it: today's sessions, anything behind you that was never recorded, and what is coming up. Tap a session to open it."
        ]),
        Part(id: "Logging a session", body: [
            "Done as planned writes the planned length and the done mark, nothing else — for the sessions that went as planned.",
            "Log details opens the form: duration, distance, pace or speed, heart rate, effort, notes. A bare number in Duration means minutes; 1:15, 1h20 and 90min work too. A decimal comma is fine.",
            "On a session already recorded the same button says Adjust logged data and the form opens filled in. Only the boxes you change are written — the button counts them.",
            "From Apple Health: if Health holds a workout for that day and sport (your Garmin sends them there), it is offered at the top of the form. Use fills the boxes. Nothing is saved until you press Save. Optional — Settings → Apple Health → Stop switches it off."
        ]),
        Part(id: "Missed, Move, Swap", body: [
            "Missed writes the missed mark and an optional note. You can still log the session later if you did it after all.",
            "Move rewrites only the date and the weekday beside it. Your sheet totals by week number and sport, never by date, so the session keeps its place in every figure.",
            "Swap exchanges two sessions' days. Only sessions still to do are offered, nearest first — a done session is never swapped by accident."
        ]),
        Part(id: "Extra activities", body: [
            "Walks, yoga, breathing, a run the plan did not ask for: these go on the Extras sheet, never into the plan, so the plan's own compliance arithmetic stays honest. Counts as training is yours to set.",
            "They show on Today and in the week strip, dotted, and all of them under Settings → Extra activities."
        ]),
        Part(id: "How syncing keeps your plan safe", body: [
            "Everything you log is saved on the phone first and sent to Dropbox straight away. Until Dropbox has confirmed, it shows as waiting — in Settings and at the top of Today.",
            "Each send starts from the copy that is in Dropbox right now, writes into it, reads the result back to check it, and uploads it against the exact version it started from. If the file changed in between — the web app, Excel on the laptop — Dropbox refuses, and the app starts again from the newer copy. Nothing is ever overwritten, and nothing you logged is lost.",
            "A row is checked before it is written into. If the session was changed in Excel into something else, the log is kept waiting with the reason rather than written into the wrong place."
        ]),
        Part(id: "Photographs", body: [
            "A session or an extra can carry photographs. They live on this phone beside the plan, never inside it: the workbook stays the record, and the iPhone's own backup covers the pictures. Settings → Photos saves them all out, and brings in the web app's export.",
            "A photo is shown only against a session whose sport still matches the row it was taken against — a row inserted in Excel slides every session onto its neighbour's identity, and a picture against the wrong session is worse than one you have to look for. Nothing is dropped: it is counted and exported."
        ]),
        Part(id: "Still in the web app", body: [
            "The Progress tab, spoken logging and the calendar export are in the web app for now. Both apps write to the same plan and check Dropbox's version first, so you can use them side by side."
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Self.parts) { part in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(part.id).font(.headline).foregroundStyle(Theme.text)
                        ForEach(part.body, id: \.self) { p in
                            Text(p).font(.body).foregroundStyle(Theme.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                }
            }
            .padding(16).padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("How this works")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WhatsNewView: View {
    struct Release: Identifiable {
        var id: String { version }
        let version: String
        let date: String
        let headline: String
        let items: [String]
    }

    static let releases: [Release] = [
        Release(version: "1.0 (17)", date: "15 September 2026", headline: "The AMS Workout Sync app", items: [
            "From today this is the primary Workout Sync: one-tap, the log form, corrections, missed, move and swap, extra activities, photographs and Apple Health, all writing into your plan exactly as the web app did — proven on 651 scenarios, then on your own plan.",
            "The web app stays for the Progress tab, spoken logging and the Mac. Both write to the same plan and check Dropbox's version first, so they can be used side by side."
        ]),
        Release(version: "0.5 (16)", date: "15 September 2026", headline: "Next 3 sessions", items: [
            "Coming up on Today is always the next three sessions, so it says so."
        ]),
        Release(version: "0.5 (15)", date: "15 September 2026", headline: "A Key button on the week card", items: [
            "The word beside This week is a small button now. Tapping the card still works too."
        ]),
        Release(version: "0.5 (14)", date: "15 September 2026", headline: "Colours and shapes in Settings", items: [
            "The key — recorded, still to do, missed, extra, rest day, and each sport's colour — is now always in Settings as well as one tap away on the This week card."
        ]),
        Release(version: "0.5 (13)", date: "15 September 2026", headline: "Plan is now Sessions", items: [
            "The middle tab holds every session in every state — upcoming, done, missed, all — and two of those are the past, so \"Plan\" was the wrong word for it. Sessions, as you chose."
        ]),
        Release(version: "0.5 (12)", date: "15 September 2026", headline: "Photographs", items: [
            "A session or an extra can carry photographs, from the library or the camera, shrunk to a size a phone can hold a season of. Tap one to see it full size, share it or delete it.",
            "They stay on this phone — never in the workbook, never in Dropbox — and the iPhone's own backup includes them. Settings → Photos saves them all out as a zip, or brings in the zip the web app's Save them all makes, so your pictures from there come across.",
            "A photograph is never shown against a session whose sport no longer matches its row; it is still counted and still exported."
        ]),
        Release(version: "0.4 (11)", date: "15 September 2026", headline: "A heart on the button, the week key, and a warning", items: [
            "The log button carries a small heart and the word Garmin when Apple Health holds a workout for that day and sport — the numbers are one tap away inside.",
            "Tap the This week card and it explains its own drawing: recorded, still to do, missed, extra, rest day, and the sport colours.",
            "If logging has waited a full day to reach Dropbox, Today says so at the top, with the reason and a Send it now button. Silent below that."
        ]),
        Release(version: "0.4 (10)", date: "15 September 2026", headline: "Stop using Apple Health", items: [
            "Settings → Apple Health has a Stop button: the app then never asks Health for anything again, and Use again turns it back on. iOS does not let an app give its own permission back, so the permission itself is taken away in the Health app — the row says where, and opens it for you."
        ]),
        Release(version: "0.4 (9)", date: "15 September 2026", headline: "How this works, and What's new", items: [
            "This guide and this list, as the web app has them.",
            "Read it again now is a button."
        ]),
        Release(version: "0.4 (8)", date: "15 September 2026", headline: "Apple Health", items: [
            "The log form offers the day's workouts from Apple Health — your Garmin sends them there — and Use fills duration, distance, heart rate and pace. Nothing is saved until you press Save. Health is only read, never written.",
            "The tag at the top of Today now says something only when there is something to say: Sending…, N waiting, or TEST COPY."
        ]),
        Release(version: "0.3 (7)", date: "15 September 2026", headline: "Extra activities", items: [
            "Walks, yoga, breathing and anything else outside the plan, written to the Extras sheet exactly as the web app writes them — the sheet is created if the workbook has none.",
            "Settings tidied: one way to choose the plan, small buttons on the rows they act on."
        ]),
        Release(version: "0.2 (6)", date: "15 September 2026", headline: "Missed, Move and Swap", items: [
            "Missed with an optional note. Move to a date. Swap with a nearby session — only sessions still to do are offered, and a move never hides that a session is done."
        ]),
        Release(version: "0.2 (5)", date: "15 September 2026", headline: "The log form", items: [
            "How did it go? for a session still to do; Adjust logged data, opening filled in, for one already recorded. Only the boxes you change are written."
        ]),
        Release(version: "0.2 (4)", date: "14 September 2026", headline: "The first write from the iPhone", items: [
            "Done as planned. Every write goes through a writer proven to produce exactly the file the web app produces, over 513 scenarios on your own plans."
        ]),
        Release(version: "0.1 (3)", date: "14 September 2026", headline: "Dropbox", items: [
            "Connect Dropbox and choose the plan inside it."
        ]),
        Release(version: "0.1 (1)", date: "14 September 2026", headline: "Read only", items: [
            "Today, Plan and a session's details, read from the plan in Files. Reading proven identical to the web app on 421 sessions."
        ])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Self.releases) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(r.version).font(.headline).foregroundStyle(Theme.text)
                            Spacer()
                            Text(r.date).font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Text(r.headline).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.today)
                        ForEach(r.items, id: \.self) { item in
                            Text(item).font(.body).foregroundStyle(Theme.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                }
            }
            .padding(16).padding(.bottom, 32)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
    }
}
