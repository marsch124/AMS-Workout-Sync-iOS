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
            "Your training plan lives in an Excel workbook in Dropbox. This app reads it, shows you the week and the day, and writes what you did back into the cells that are already there.",
            "It writes nothing anywhere else. Every other part of the workbook is copied through untouched.",
            "Four tabs along the bottom, each in its own colour: swipe between them or tap one. Tapping the tab you are already on comes back to that tab's first screen, whatever you had opened."
        ]),
        Part(id: "Today", body: [
            "The week strip is one column a day, one bar a session. A solid block is recorded, a lighter block of the same colour is still to do, hatched is marked missed, dotted is an extra outside the plan. The rest day is a flat line. Tap the card for the key.",
            "A done session carries a small green tick in the corner of its bar. An extra carries the same tick in a paler green: it is something you did, and it is not part of the plan.",
            "Beside the hours, a hairline: how much of the week's planned time is recorded, and a faint notch marking where the week stands once tonight is done.",
            "Under it, one block for every quarter hour of extra activity that counts as training, every fourth in amber — an hour a yellow block. Extras are never counted in the week's hours.",
            "Below it: today's sessions, anything behind you that was never recorded, and tomorrow on its own pale blue ground. Tap a session to open it."
        ]),
        Part(id: "Logging a session", body: [
            "The green Done button carries the planned length — Done · 1h 05m — and writes that length and the done mark, nothing else, for a session that went as planned. It sits in one row with Log details, Missed and Move, all the same size.",
            "Log details opens the form: duration, distance, pace or speed, heart rate, effort, notes. A bare number in Duration means minutes; 1:15, 1h20 and 90min work too. A decimal comma is fine.",
            "On a session already recorded, a small round pen opens the form filled in — on the session itself, beside the figures, and on its row in the Sessions list, so a typo is mended without opening anything. Only the boxes you change are written — the button counts them. Missed and Move are gone by then; they no longer apply. What you wrote in Notes is shown under the session's figures, above the photographs.",
            "From Apple Health: every workout Health holds for that day is offered at the top of the form, the one matching the session's sport first — whatever Garmin filed it as, it is there to use. Use fills the time, the distance and the heart rate; the pace is yours to type from Garmin Connect, because Garmin does not pass it to Health. Nothing is saved until you press Save.",
            "Settings → Apple Health says what Health is handing over today and yesterday. Both lists empty while your watch has something means the app is not being given it: open Health → your picture → Apps → Workout Sync and switch the rows on. Stop switches the whole thing off."
        ]),
        Part(id: "The Sessions tab", body: [
            "Four lists — Upcoming, Done, Missed, All — each with the number of things in it. The words stay at the top while the list scrolls under them, so choosing another list never means scrolling back.",
            "Sessions and extra workouts are listed together under Done and All, each on the day it happened."
        ]),
        Part(id: "Missed, Move, Swap", body: [
            "Missed writes the missed mark and an optional note. You can still log the session later if you did it after all.",
            "Move rewrites only the date and the weekday beside it. Your sheet totals by week number and sport, never by date, so the session keeps its place in every figure.",
            "Swap exchanges two sessions' days. Only sessions still to do are offered, nearest first — a done session is never swapped by accident."
        ]),
        Part(id: "Extra workouts", body: [
            "Walks, yoga, rowing, breathing, a run the plan did not ask for: these go on the Extras sheet, never into the plan, so the plan's own compliance arithmetic stays honest. Counts as training is yours to set — a swim, bike, run, strength or rowing counts unless you say otherwise; a walk or a meditation does not unless you say it does.",
            "Add one with the small Extra workout pill at the end of the Tomorrow line on Today. Each kind carries its own hand-drawn mark in its own colour. They show on Today and in the week strip, dotted, on the Sessions tab under Done and All, and all of them together under Settings → Extra workouts.",
            "The round pen on its card opens it for changing — in the Sessions list or on its own screen. Only the boxes you alter are written back into its row, so correcting the length leaves everything else exactly as it was, and emptying a box empties the cell. Until it reaches Dropbox it reads as waiting to sync, like anything else you log.",
            "Photographs follow an extra when you change it, even when you change the day, the activity or the length it is known by."
        ]),
        Part(id: "How syncing keeps your plan safe", body: [
            "Everything you log is saved on the phone first and sent to Dropbox straight away. Until Dropbox has confirmed, it shows as waiting — in Settings and at the top of Today.",
            "Each send starts from the copy that is in Dropbox right now, writes into it, reads the result back to check it, and uploads it against the exact version it started from. If the file changed in between — Excel on the laptop, or anything else that saved it — Dropbox refuses, and the app starts again from the newer copy. Nothing is ever overwritten, and nothing you logged is lost.",
            "A row is checked before it is written into. If the session was changed in Excel into something else, the log is kept waiting with the reason rather than written into the wrong place."
        ]),
        Part(id: "Photographs", body: [
            "A session or an extra can carry photographs. They live on this phone beside the plan, never inside it: the workbook stays the record, and the iPhone's own backup covers the pictures. Settings → Photos saves them all out, and brings in the web app's export.",
            "Adding one happens behind the pen: open the form and press Add photo, which asks whether to take one now or pick from your photos. A picture is kept the moment you add it — there is nothing to save, and the Save button only ever writes the boxes you changed. In the Sessions list, the first three of a session's pictures sit in the corner of its row, beside the pen.",
            "A photo is shown only against a session whose sport still matches the row it was taken against — a row inserted in Excel slides every session onto its neighbour's identity, and a picture against the wrong session is worse than one you have to look for. Nothing is dropped: it is counted and exported."
        ]),
        Part(id: "Progress", body: [
            "The flag beside the weeks to go holds what the race is — distances, where, and the day — and under it the phases of the season: each one's colour, the name your sheet gives it, and how many weeks it lasts.",
            "Nothing here is read from the Progress sheet — its cells are formulas that carry Excel's last answer, and the app never recalculates them. Every figure is worked out from the session rows each time the screen opens, and none of it is stored.",
            "The road: weeks to the race, the phases as one bar with today marked on it — each phase in its own colour, cool early in the season and warm near the race, today's at full strength and the weeks ahead faint — sessions done, hours banked against hours due. Is it working: distance per heartbeat, the first half of your logged easy sessions against the last, one sport at a time — it says nothing until eight sessions of a sport carry a distance, a time and a heart rate. Twelve weeks: the hours you did against the line the plan asked for. Then what was kept: completed, missed, unanswered; the run you are on; which sport runs behind; missed against moved."
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
            "Any box takes dictation: the microphone on the keyboard."
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
        Release(version: "1.1 (58)", date: "2 October 2026", headline: "The extras lose their dots", items: [
            "An extra workout in the week strip is its dotted outline and nothing inside it: the line of dots down the middle is gone, as you asked. The key shows the same."
        ]),
        Release(version: "1.1 (57)", date: "1 October 2026", headline: "The phases have colours and names", items: [
            "The phase bar on Progress is no longer four greys: each phase has its own colour, cool at the start of the season and warm towards the race, so the bar reads at a glance. Today's phase is at full strength, the ones behind you and ahead of you a little lighter.",
            "The bar used to run out of its card on the right. Your sheet has a four-week postseason after race day, and the bar is measured in days to the race, so the blocks came to more than the whole road. It stops at the race now, and a phase that falls after it says so instead of giving a length.",
            "The flag beside the weeks to go now also lists the phases under the race: the colour, the name your sheet gives it, and how many weeks long it is. The bar had nothing to say what its blocks were.",
            "Tap the tab you are already on and it goes back to that tab's own first screen — out of a session, out of a list, without pressing Back.",
            "What Health hands over is a switch now rather than a button."
        ]),
        Release(version: "1.1 (56)", date: "1 October 2026", headline: "Nothing left that can bring it down", items: [
            "The last places where an unexpected answer from the phone or the network would have stopped the app now stop only what they were doing — the calendar's dates, the sign-in address, a time zone.",
            "Four more tests of how an extra workout reaches your sheet: it lands on the first empty row and never over one in use, it reads back as itself, sending it twice does not double it, and a correction writes only the boxes you altered."
        ]),
        Release(version: "1.1 (55)", date: "30 September 2026", headline: "Disconnect tells you what is still waiting", items: [
            "Settings → Dropbox now says how many entries are still to be sent before you disconnect. They stay on this phone either way, but nothing reaches Dropbox until you connect and choose the plan again."
        ]),
        Release(version: "1.1 (54)", date: "30 September 2026", headline: "The pictures, not a camera", items: [
            "On Today, a session or an extra with photographs shows them — up to three, in the corner of its card — instead of a camera and a number. The Sessions list already did; Today had been left behind."
        ]),
        Release(version: "1.1 (53)", date: "30 September 2026", headline: "Your waiting logging cannot go missing", items: [
            "Anything logged but not yet sent to Dropbox lives in one file on this phone. If that file could not be read — which an app update could have caused on its own — the app used to start with an empty queue and say nothing. It now reads what it can, keeps a copy of anything it cannot, and tells you.",
            "A record written by an older version of the app reads correctly, with the numbers you put in it."
        ]),
        Release(version: "1.1 (52)", date: "30 September 2026", headline: "Hardening: nothing new, less to go wrong", items: [
            "A date the sheet cannot mean — a thirteenth month, a 31st of February — is refused instead of quietly becoming another day. A garbled date in the Extras sheet used to place the row in the wrong week.",
            "The part of the app that talks to Dropbox can no longer be brought down by an odd answer from the network: every such case now fails the sync, with a reason, instead of the app.",
            "Twenty-four new tests of the reading and writing itself, run on every push beside the ones that drive the screens. They already found the date fault above."
        ]),
        Release(version: "1.1 (51)", date: "30 September 2026", headline: "Plainer week, plainer words", items: [
            "A session still to do is a lighter block of its sport's colour in the week strip, with no frame around it.",
            "Extra activity is Extra workout, everywhere the app says it.",
            "Counts as training is a mark now instead of the words — the same little blocks the week bar draws that time in. A workout that does not count carries nothing.",
            "A photograph added while the form is open no longer meets \"nothing has changed\": pictures are kept the moment you add one, so the button simply says Done and closes.",
            "How this works has been brought up to date: the Sessions tab and its four lists, the pen on a row, photographs behind the pen, what Apple Health hands over, and the extra workouts' own marks."
        ]),
        Release(version: "1.1 (50)", date: "30 September 2026", headline: "Mend it from the list", items: [
            "Every session and extra already done carries its pen in the list itself, so a typo is corrected without opening it first.",
            "Beside the pen, up to three of that session's photographs, pen-sized.",
            "Photographs are added behind the pen now, not from the screen at rest — and by one button instead of two: Add photo asks whether to take one or pick from your photos."
        ]),
        Release(version: "1.1 (49)", date: "30 September 2026", headline: "Three things he pointed at", items: [
            "Each tab keeps its own colour whether it is open or not, and the open one sits on a patch of that colour.",
            "What kind of thing is a proper box now, carrying the activity's own badge in its own colour instead of a bare green word.",
            "A session still to do has no frame around it. Done and missed still say so with one.",
            "On an extra's own screen the pen is a round button inside the card, in the bottom corner under the tick."
        ]),
        Release(version: "1.1 (48)", date: "30 September 2026", headline: "Every extra activity has its own icon", items: [
            "Yoga sits cross-legged, Walk walks, Hike carries a pack and a pole, Ski stands on its skis — drawn in the same hand as the swim, the bike, the run and the weight, and no longer borrowing them.",
            "In Settings, Read Health again says what it does, and Ask iOS for access only appears when nothing at all is coming through — there is no reason for it the rest of the time."
        ]),
        Release(version: "1.1 (47)", date: "30 September 2026", headline: "Health works again", items: [
            "Apple Health could not be read at all since build 40: the upload left out the app's HealthKit permission, so iOS refused every question and the app looked as if Health had nothing. It is back, and the upload now refuses to send a build that lacks it.",
            "The extra-activity blocks sit lower, clear of the week's hairline.",
            "A card's small labels stay on one line each and take the next row when they run out of width. Three of them — a length, Counts as training and Waiting to sync — used to squeeze until \"Counts as training\" stood three words high."
        ]),
        Release(version: "1.1 (46)", date: "30 September 2026", headline: "Rowing is a rowing machine", items: [
            "The Rowing icon is the machine itself — fan, rail, seat and the monitor on its arm — drawn by hand like the rest. The crossed oars are gone: shown at the size the app actually draws them, without a label, they said nothing.",
            "Chosen by looking: six candidates in the card they live in, no names, and the one that was recognised won."
        ]),
        Release(version: "1.1 (45)", date: "30 September 2026", headline: "Health says why", items: [
            "Under What Health hands over there is now a line saying when Health was last asked, how many workouts it gave for the last seven days, and whether it gives anything at all. If Health returned an error it is printed in red — the app used to throw that error away, which is why a refusal and an empty day looked the same.",
            "Ask again always leaves something new on screen, and beside it Ask iOS again puts the permission question to iOS once more."
        ]),
        Release(version: "1.1 (44)", date: "30 September 2026", headline: "Health, today and yesterday", items: [
            "Settings → Apple Health has a toggle, What Health hands over. It opens two lists: what Apple Health has today, and what Apple Health had yesterday — because yesterday is usually the day in question, and a list that knew only about today said \"nothing\" on a rest morning.",
            "Both lists empty while your watch has something means the app is not being given it: Health → your picture → Apps → Workout Sync, switch the rows on, then Ask again."
        ]),
        Release(version: "1.1 (43)", date: "29 September 2026", headline: "Health hands over everything it has", items: [
            "A session's form now offers every workout Apple Health holds for that day, the matching sport first. It used to show only the ones whose sport agreed, and say there was nothing at all otherwise — so a run Health had filed as another kind of workout was invisible, and the day looked empty.",
            "Settings → Apple Health lists what Health hands over for today. iOS never tells an app whether reading was allowed, so a refused read looks exactly like an empty day; this line tells the two apart. If it says nothing while your watch has something, open Health → your picture → Apps → Workout Sync and switch the rows on."
        ]),
        Release(version: "1.1 (42)", date: "29 September 2026", headline: "Rowing, and the four lists stay put", items: [
            "Rowing is an extra activity of its own, after Strength, with its own oars and its own teal — and it counts as training unless you say otherwise. A rowing workout from Garmin fills its form like any other.",
            "On Sessions, the four words — Upcoming, Done, Missed, All — stay at the top while the list scrolls under them.",
            "Save is never a dead grey button. Pressed before there is anything to save, it says what it wants; it used to go quietly nowhere, which is how a walk could look saved and not be.",
            "When Apple Health is switched off or not yet connected, the form says so and offers to put it back on. Before, it simply showed nothing and looked broken.",
            "An extra that counts always draws at least one block under the week bar; under eight minutes it used to draw none.",
            "The week's key explains the blocks: only extras marked as counting are in them."
        ]),
        Release(version: "1.1 (41)", date: "27 September 2026", headline: "Extra activities have their own bar", items: [
            "Under the week's hairline on Today there is now a second row: one block for each quarter hour of extra activity that counts as training, every fourth block in amber, so a yellow block is an hour done. Extras stay out of the week's figures, as before — this is beside the plan, never inside it.",
            "An extra marked as not training load adds nothing to it."
        ]),
        Release(version: "1.1 (40)", date: "23 September 2026", headline: "The pen sits with the numbers", items: [
            "The pen is on the What you did line, beside the figures it edits. On a session logged a moment ago, which has no figures until it syncs, it stays under the card so it is never out of reach."
        ]),
        Release(version: "1.1 (38)", date: "23 September 2026", headline: "A pen instead of the word", items: [
            "Adjust is a small grey button carrying a hand-drawn pen, with no word on it, on a logged session and on an extra. It still says Adjust logged data aloud for VoiceOver."
        ]),
        Release(version: "1.1 (37)", date: "23 September 2026", headline: "The same app, sent a new way", items: [
            "Nothing in the app itself changed. This build was sent to TestFlight by GitHub rather than from the Mac, to prove that path works — so a change made while the Mac is off can still reach your phone."
        ]),
        Release(version: "1.1 (36)", date: "22 September 2026", headline: "One row of buttons, your words further up, and marks for breathing and meditation", items: [
            "On a session still to do, all four buttons are now one row at one size: Done (with the planned length on it), Log details, Missed, Move. Done keeps its green fill — it is still the one that finishes the session — but it no longer takes the whole screen.",
            "On a session you have logged, your note is shown directly under the figures, above the photographs, instead of below everything.",
            "Breathing extras carry a pair of lungs and meditation extras a lotus, both hand-drawn, instead of a tick — which, beside the done tick every extra now carries, made two ticks on one card.",
            "A long note on a logged session is shown in full; its last line used to be cut off. And at night the grey of breathing, meditation and rest is lighter, so their names and marks can be read."
        ]),
        Release(version: "1.1 (35)", date: "22 September 2026", headline: "Garmin for extras too", items: [
            "An extra activity's form now offers the day's workouts from Apple Health, as a session's form does — for a new extra and when you adjust a saved one. Use fills the time, the distance and the heart rate; a new extra also takes the workout's kind. Nothing is saved until you press Save.",
            "An extra's card carries the done tick everywhere it appears — Today, Sessions under Done and All, Settings, its own screen — in the paler green the week strip gives extras.",
            "An extra's own screen shows the same small grey Adjust as a logged session, instead of a green button."
        ]),
        Release(version: "1.1 (34)", date: "22 September 2026", headline: "Extras: corrected, listed under Done, ticked", items: [
            "An extra activity can be changed after it is saved. Open it — from Today, from Sessions under Done, or from Settings → Extra activities — and press Adjust. The form opens filled in with what the sheet holds, and only the boxes you change are written into its own row; the button counts them before you press it. A box you empty empties the cell.",
            "Extras are now listed on the Sessions tab under Done and under All, in the day they happened, beside that day's sessions. They used to be on Today for a day and after that only under Settings.",
            "Each extra in the week strip carries the same small tick as a done session, in a paler green — it is something you did, and it is still not part of the plan."
        ]),
        Release(version: "1.1 (33)", date: "21 September 2026", headline: "Extra activity on the Tomorrow line", items: [
            "The Extra activity button is a small pill on the Tomorrow line, beside the blue Tomorrow tab on the page's own ground, instead of a full-width row of its own. On a day with no Tomorrow block it sits alone on the right."
        ]),
        Release(version: "1.1 (32)", date: "21 September 2026", headline: "The pace is yours; done bars carry a tick", items: [
            "Use from Apple Health fills time, distance and heart rate, and no longer works out a pace or a speed. Garmin's own pace is not in Apple Health, and a sum from the whole session was wrong for any workout with rest in it: a 1:56 swim came out as 3:39. Type the pace from Garmin Connect.",
            "Each done session in the week strip carries a small green tick, the same sign as on a done session card."
        ]),
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
