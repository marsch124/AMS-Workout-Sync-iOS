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
            "Beside the hours, a hairline: how much of the week's planned time is recorded, and a faint notch marking where the week stands once tonight is done.",
            "Below it: today's sessions, anything behind you that was never recorded, and tomorrow on its own pale blue ground. Tap a session to open it."
        ]),
        Part(id: "Logging a session", body: [
            "Done as planned writes the planned length and the done mark, nothing else — for the sessions that went as planned.",
            "Log details opens the form: duration, distance, pace or speed, heart rate, effort, notes. A bare number in Duration means minutes; 1:15, 1h20 and 90min work too. A decimal comma is fine.",
            "On a session already recorded, a small grey Adjust opens the form filled in. Only the boxes you change are written — the button counts them. Missed and Move are gone by then; they no longer apply.",
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
        Part(id: "Progress", body: [
            "The flag beside the weeks to go holds what the race is — distances, where, and the day. It is a tap because it is the one thing on that screen you already know.",
            "Nothing here is read from the Progress sheet — its cells are formulas that carry Excel's last answer, and the app never recalculates them. Every figure is worked out from the session rows each time the screen opens, and none of it is stored.",
            "The road: weeks to the race, the phases as one bar with today marked on it, sessions done, hours banked against hours due. Is it working: distance per heartbeat, the first half of your logged easy sessions against the last, one sport at a time — it says nothing until eight sessions of a sport carry a distance, a time and a heart rate. Twelve weeks: the hours you did against the line the plan asked for. Then what was kept: completed, missed, unanswered; the run you are on; which sport runs behind; missed against moved."
        ]),
        Part(id: "Your zones", body: [
            "A session's Z2 or Z4–Z5 is a pill on its screen. Tap it and the app says what that is for you this season — heart rate always, bike power on a ride once an FTP is entered, the swim paces on a swim — read from the Test Results & Zones sheet of your workbook, from your latest test. The app never works a zone out itself.",
            "The whole sheet, the current numbers and the words it uses, is under Settings → Your zones.",
            "The numbers come from your latest test row. The zone tables are your sheet's own formulas: if another program saves the file without the answers Excel worked out, the tables show a dash until you open the plan in Excel once and save it."
        ]),
        Part(id: "In your calendar", body: [
            "Settings → Calendar → Put them in writes every session from today to the end of the plan into a calendar called Training: at six in the morning (or the hour you set), each as long as it is planned, one after the other on a day with two. Each is headed by the sport and its length and nothing else — Run 35, Swim 40, Bike 2h30min — with the session's own words in the notes. A rest day is an all-day event. The events float, so six stays six wherever the phone is.",
            "Or choose All day, and every session becomes an all-day event on its own day instead, still headed by the sport and its length.",
            "The app keeps them right: a moved session moves its event, a changed row rewrites it, a session that disappears takes its event with it. Days already behind are left as they were. The Training calendar is the app's own — from today onwards it holds the plan and nothing else — and Take them out removes it."
        ]),
        Part(id: "Sending a session", body: [
            "The share button at the top of a session offers the whole session — the brief, for a training partner — and, once it is done, what you did: one sentence for the person at home, with the time and the distance. Photos on the session go along. Heart rate and effort never do."
        ]),
        Part(id: "Speaking instead of typing", body: [
            "Any box takes dictation: the microphone on the keyboard. The web app's spoken logging is not needed here."
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
        Release(version: "1.1 (31)", date: "21 September 2026", headline: "Swim pace as Garmin shows it", items: [
            "The swim pace filled in from Apple Health counted the rest between sets as swimming: a 1:56 swim came out as 3:39. It now uses only the time you were actually swimming — the lengths, or failing those the watch's laps and pauses — as Garmin does.",
            "A swim already saved with the wrong pace: open it, press Adjust, then Use on the Garmin swim, and Save — only the pace changes."
        ]),
        Release(version: "1.1 (30)", date: "21 September 2026", headline: "A logged session stops asking", items: [
            "Once a session is logged, Missed and Move are gone: they no longer apply. A small grey Adjust stays for fixing a typo.",
            "Logged with one tap and your Garmin workout is in Apple Health? A small Fill from Garmin stays until the watch's numbers are in, then it goes too. The app knows they are in when you used them in the form, or when the recorded time and distance match the watch's.",
            "On a session still to do, Done as planned stays the one big button; Log details, Missed and Move are small, in one row.",
            "The week's hours on Today now add up the time you actually recorded — a 47-minute swim counts 47 — instead of each done session's planned length. Only a session marked done without a time still counts as planned."
        ]),
        Release(version: "1.1 (29)", date: "20 September 2026", headline: "The four disciplines along the bottom", items: [
            "The tab bar now carries the sports: swim for Today, bike for Sessions, run for Progress, strength for Settings. The words are unchanged, and each icon still takes its page's colour."
        ]),
        Release(version: "1.1 (28)", date: "20 September 2026", headline: "One size of button in Settings", items: [
            "Every button on the Settings screen is now the same size, and it is the small one: the full-width buttons for choosing the plan and connecting Dropbox are gone.",
            "Settings → Calendar can put the sessions in as all-day events instead of at an hour. Choose At a time or All day; everything from today onwards changes over."
        ]),
        Release(version: "1.1 (27)", date: "20 September 2026", headline: "Four small things you asked for", items: [
            "Under the week's hours on Today: a hairline showing how much of the planned time is recorded, with a faint notch where the week stands once tonight is done.",
            "Tomorrow sits on its own pale blue ground, so the eye knows at once that everything below it is no longer today.",
            "Sessions shows how many are upcoming, done and missed, the number under each word.",
            "Progress no longer carries the race description. It is behind the small flag beside the weeks: tap it for the race's own words, tap again and it goes.",
            "Settings is quieter: Read it again now is a small grey line under Change, and what the app made of your sheet is one grey line instead of a section. The photo buttons are small.",
            "Your zones now read your latest test's own numbers, so they show even when the file has lost what Excel worked out. When the zone tables themselves are empty, the app says why and what to do about it."
        ]),
        Release(version: "1.1 (26)", date: "18 September 2026", headline: "Short headings in the calendar", items: [
            "A calendar event is now headed by the sport and its length and nothing else: Run 35, Swim 40, Bike 2h30min. The session's own words are still there, in the event's notes. Events from today onwards are rewritten the next time the app opens; days already behind keep the heading they had."
        ]),
        Release(version: "1.1 (25)", date: "16 September 2026", headline: "Red where something is taken away", items: [
            "Stop under Apple Health and Take them out under Calendar are red now, like Disconnect and Discard: every button that takes something away is red, every other one green."
        ]),
        Release(version: "1.1 (24)", date: "16 September 2026", headline: "Zones, the calendar, and sending a session", items: [
            "Tap a session's Z2 or Z4–Z5 and the app says what that is for you — heart rate, bike power, swim paces — from the Test Results & Zones sheet of your workbook, from your latest test. The whole sheet is under Settings → Your zones.",
            "Settings → Calendar → Put them in keeps every session from today onwards in a Training calendar, at the hour you set and as long as it is planned, and keeps the events right when sessions move.",
            "The share button on a session sends the whole session, or, once it is done, what you did, with its photos.",
            "How this works no longer points at the web app: the phone app is the app."
        ]),
        Release(version: "1.1 (23)", date: "16 September 2026", headline: "Bike and strength told apart", items: [
            "The bike's yellow is brighter and the strength orange stronger, so the two no longer look alike in the week bars and on the badges. The web app uses the same two colours from v1.72.2. (Build 22 carried a quieter version of the same change.)"
        ]),
        Release(version: "1.1 (21)", date: "16 September 2026", headline: "The wave is back", items: [
            "The app icon is the green training wave on dark teal again — the web app's icon, redrawn with one even stroke, equal peaks and round corners. The calendar from build 20 is gone."
        ]),
        Release(version: "1.1 (20)", date: "15 September 2026", headline: "Progress", items: [
            "The Progress tab, as in the web app: the road to the race with the phases as one bar, is it working (distance per heartbeat, then against now), twelve weeks against what they asked for, where the hours went by sport, and what was kept — consistency, the sport that runs behind, missed or moved. Every figure checked against the web app's on the same workbooks: no differences.",
            "Moves made in this app are remembered on this phone for the missed-or-moved figure, as the web app remembers its own.",
            "A new app icon (replaced again in build 21).",
            "Swipe reaches Progress like the other pages."
        ]),
        Release(version: "1.0 (19)", date: "15 September 2026", headline: "Tomorrow, not the next three", items: [
            "Under today's sessions, Today now shows only tomorrow's — a rest day included — instead of the next three sessions."
        ]),
        Release(version: "1.0 (18)", date: "15 September 2026", headline: "Swipe between the screens", items: [
            "Today, Sessions and Settings are pages: swipe left or right to move between them, or tap the bar as before.",
            "The date is gone from the top of Today — it is always today — and the room went to the week and the sessions."
        ]),
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
