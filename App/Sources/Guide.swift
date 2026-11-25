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
            "This app is called AMS Triathlon Training; under its icon on the home screen it reads Triathlon. It used to be called Workout Sync. It is the same app with the same data, and there is nothing to set up again.",
            "Your training plan lives in one of two places, and you choose. Until you move it, it is your Excel workbook in Dropbox: the app reads it, shows you the week and the day, and writes what you did into the cells that are already there, and nothing anywhere else. Once you have moved it, the plan lives in this app. The next part, Where the plan lives, tells you how.",
            "Everything else in this guide works the same either way. Where the two differ, it says so.",
            "Four tabs along the bottom, each in its own colour, each with a quarter of the bar to itself: the one you are on is that whole quarter in its colour. Swipe between them or tap one. Tapping the tab you are already on comes back to that tab's first screen, whatever you had opened.",
            "That is the iPhone. On an iPad, and on a Mac, the bar along the bottom is a list down the left side instead: Today, Week, Season, Sessions, Progress, Settings. The part On iPad and Mac, further down, says what is different there. The same plan shows on all three; The same plan on all your devices tells how."
        ]),
        Part(id: "Where the plan lives", body: [
            "Until now your plan lived in the Excel file in Dropbox, and this app was a guest. From 2.0 you can move it into this app. If you do nothing, nothing changes.",
            "To move it: Settings → Your plan → Move the plan into this app → Start. Then tap Take the plan in and count. The app reads your Excel file afresh and counts the plan twice: as Excel has it, and as the app holds it.",
            "Excel and the app, side by side shows both counts for sessions, training, rest days, done, missed, still to come, extra workouts and minutes. Green same means they agree. Red differs means they do not. Month by month shows the same for each month.",
            "Looked odd in the file lists strange things, such as a pace that cannot be or a session on a rest day. They are taken in as written. Correct them later with the pen.",
            "When all is the same, the page says Everything matches. and shows the button Make this app the plan's home. Nothing is saved until you tap it. Entries still waiting for Dropbox must be sent first.",
            "After the switch, logging, Missed, Move, Swap, extra workouts and How hard was it? are saved in the app at once, also without internet. Nothing is written into your Excel file any more. It stays as it was, and whatever you change there, the app does not see.",
            "Settings → Your plan then says Lives in this app, with the day you moved it.",
            "Safety copies: the plan as it was at the start of each day the plan changed, kept for 30 days. Settings → Safety copies lists them and puts one back; see How your plan is kept safe.",
            "Spreadsheet copy: Save a copy now makes a spreadsheet of the plan as it is today, to keep or send. The app also makes one about once a week, in Files → On My iPhone → Triathlon, and keeps the newest eight. It checks each copy against the plan first. A copy does not change after it is made.",
            "Copy in Dropbox: while Dropbox is connected, the app also saves the plan there as a spreadsheet named Triathlon plan from the app, beside your Excel file. It is written a little after each change and never read back. Settings → Your plan → Copy in Dropbox says when.",
            "Going back: for three weeks, the red button Go back to Excel writes the plan as it is now into your Excel file in Dropbox. Excel is then the plan's home again. If that file changed in the meantime, the app refuses and does nothing. After three weeks the button is gone; the spreadsheet copies stay.",
            "From 2.2 the plan can be on your iPad and your Mac too. The plan has to live in the app on your iPhone first: until you have moved it in, there is nothing to share. Once it has, it goes to your own iCloud by itself and your iPad and Mac fetch it. Going back to Excel stays possible for three weeks, but not once an iPad or a Mac is using the plan; then the way out is a spreadsheet copy. See The same plan on all your devices.",
            "Once your iCloud holds a plan that was moved in on another device, the page The plan moves in, on an iPhone that is still on Excel, says so and shows the green button Use the plan from iCloud instead of a second import. It brings that plan here, so the iPhone shows the same plan as your other devices, and anything still waiting on the iPhone is written into it. Your Excel file is not changed."
        ]),
        Part(id: "The same plan on all your devices", body: [
            "Your iPhone, your iPad and your Mac can show the same plan, everything you log and change, and your answers to How do you feel? and How hard was it? It goes through your own iCloud, in a folder that belongs to this app. Nothing is sent anywhere else, and nobody else can see it.",
            "Each device keeps its own full copy of the plan and works without internet. When a device has iCloud, it meets the copy there: it puts up what is new here and takes down what is new elsewhere. This happens when you open the app, a moment after you change something, and about every half minute while the app is open.",
            "When two devices changed things while they were apart, they are joined, and nothing you logged is lost. A session has two sides: the plan side (the day, the sport, the words, the length) and the log side (what you recorded). Each side comes from the device that changed it last, so a change of plan on the iPad and a log on the iPhone both stay. A session is taken out only when somebody took it out on purpose, and a log made after that brings it back. A file that is missing, or still on its way from iCloud, is never read as an empty plan.",
            "Your iPad or Mac opens the app for the first time: it has no Excel and no Dropbox, and nothing to choose. Today says in one line, beside a coloured dot, what it is waiting for, and when the plan has arrived it says Plan from your iPhone and a count, then opens by itself. If the plan on your iPhone is still in Excel, it says so and tells you where to move it in. If you have not opened the app on your iPhone yet, it says that.",
            "Settings → iCloud is the first row under Your plan. It shows the dot with its words, when the devices last met, Sync now, Your devices (each iPhone, iPad and Mac with when it was last seen and its version), What is shared, and Copy from before iCloud. The same dot, with its words, sits at the foot of the side list on iPad and Mac.",
            "The dot always comes with its words, and the words say which: green, Same on all devices; amber, On its way; grey, iCloud is off (or this device is not signed in to iCloud); red, a problem, and the words say what. Nothing is ever changed on a device because of a problem.",
            "If your iCloud holds a plan from a second, separate move into the app, the app does not join them. Settings → iCloud shows both side by side, with their sessions, what is done and the last change, and you choose the one to use. The other is kept as a file.",
            "If a device's clock is behind, the iCloud page says so in red. Set it to the right time, so that the newest change always wins.",
            "What stays on the iPhone: Dropbox and its copy of the plan, the Training calendar (it appears in Calendar on your iPad and Mac through iCloud), and Apple Health. Health's numbers are shown on iPad and Mac with where they came from, in grey, like from iPhone, as of 07:12. Photographs, the Garmin key and the safety copies stay on the device they were made on.",
            "Getting back: every device keeps the plan it had before it first met iCloud, for good. Settings → iCloud → Copy from before iCloud has a Share button for it. Safety copies, on each device, and spreadsheet copies still work as before.",
            "If a device runs an older Triathlon than the plan in iCloud, it says Update Triathlon on this device and changes nothing. Update the app in TestFlight, then open it again."
        ]),
        Part(id: "Today", body: [
            "The week strip is one column a day, one bar a session. A solid block is recorded, a lighter block of the same colour is still to do, hatched is marked missed, dotted is an extra outside the plan. The rest day is a flat line. Tap the card for the key.",
            "A done session carries a small green tick in the corner of its bar. An extra carries the same tick in a paler green: it is something you did, and it is not part of the plan.",
            "Beside the hours, a hairline: how much of the week's planned time is recorded, and a faint notch marking where the week stands once tonight is done.",
            "Under it, one block for every quarter hour of extra activity that counts as training, every fourth in amber — an hour a yellow block. Extras are never counted in the week's hours.",
            "Below it: today's sessions, anything behind you that was never recorded, and tomorrow on its own pale blue ground. Tap a session to open it.",
            "A rest day carries a small moon. The green tick means done and nothing else.",
            "Each morning, under the green heading, a small card asks How do you feel? Five faces, a word under each: Bad, Tired, OK, Good, Great. One tap, once a day. Then the card is gone until tomorrow, and the morning line shows Feeling good (or the word you chose). Tap that word to change it. The answer stays on this phone only; it is not written into the plan. Nothing on Today reacts to it: no advice, no score.",
            "With a Garmin key saved (Settings → Garmin), a second line sits under the morning line, with Garmin's numbers. See Morning numbers from Garmin. On an iPad or a Mac, when the Health numbers are your iPhone's, a small grey line under the morning line says so, like from iPhone, as of 07:12."
        ]),
        Part(id: "Logging a session", body: [
            "The green Done button carries the planned length — Done · 1h 05m — and writes that length and the done mark, nothing else, for a session that went as planned. It sits in one row with Log details, Missed and Move, all the same size.",
            "Once a session is done, the place where the Done button was holds a row of numbers, 1 to 10: How hard was it? 1 is very easy, 7 is hard, 10 is all out. One tap saves it into the plan's Effort box. That is the same box as Effort in Log details, so there is no new box and, in Excel, no new column. If you do not answer, it simply waits on that session: no reminder, no badge.",
            "Log details opens the form: duration, distance, pace or speed, heart rate, effort, notes. A bare number in Duration means minutes; 1:15, 1h20 and 90min work too. A decimal comma is fine.",
            "On a session already recorded, a small round pen opens the form filled in — on the session itself, beside the figures, and on its row in the Sessions list, so a typo is mended without opening anything. Only the boxes you change are written — the button counts them. A session you have already recorded keeps its own record: Change (see Changing the plan) alters what was planned, the pen alters what you did. Missed and Move are gone by then; they no longer apply. What you wrote in Notes is shown under the session's figures, above the photographs.",
            "From Apple Health: every workout Health holds for that day is offered at the top of the form, the one matching the session's sport first — whatever Garmin filed it as, it is there to use. Use fills the time, the distance and the heart rate; the pace is yours to type from Garmin Connect, because Garmin does not pass it to Health. Nothing is saved until you press Save.",
            "Settings → Apple Health says what Health is handing over today and yesterday. Both lists empty while your watch has something means the app is not being given it: open Health → your picture → Apps → AMS Triathlon Training and switch the rows on. Stop switches the whole thing off.",
            "Apple Health is read for two things: to fill the log form, and, on Progress, to find workouts that are in neither the plan nor your extras (a hike, the gym). It is only read. Nothing is ever written to Health."
        ]),
        Part(id: "On a session's page", body: [
            "A session of more than 90 minutes that is still to do carries one grey line under its figures: Over 90 minutes: eat and drink as you go — about 30–60 g of carbohydrate an hour. A strength session, to do or done, carries one grey line: After strength: a meal or snack with 20–30 g of protein within an hour or two. They are general habits of sport, written for everyone alike, and not medical advice. They are only text: they change nothing, ask nothing and are never counted.",
            "A run or ride made of repeats, like 3 × 8 min at Z3, carries the Garmin card while it is still to do. Swims, strength, finished sessions and texts the app cannot read into steps have none.",
            "Folded, the card is one line, Build it like this in Garmin Connect, with a small green button Show the steps (Hide the steps when it is open). The steps: open Garmin Connect, then More → Training & Planning → Workouts → Create a Workout; choose the sport; add a warm-up, a repeat with its effort and its recovery, and a cool-down; give it a name and save it. Copy the steps copies them as text, to paste into a note or a message.",
            "Saved there, it stays in your Workouts list: copy it for next week and send it to your watch. The app itself sends nothing to the watch.",
            "The lines and the card show whether the plan is in Excel or in the app."
        ]),
        Part(id: "The Sessions tab", body: [
            "Four lists — Upcoming, Done, Missed, All — each with the number of things in it, and under them one bar for the whole plan: solid recorded, hatched missed, light still to come. The words and the bar stay at the top while the list scrolls under them, so choosing another list never means scrolling back.",
            "Sessions and extra workouts are listed together under Done and All, each on the day it happened."
        ]),
        Part(id: "On iPad and Mac", body: [
            "On an iPad, and on a Mac (where the app is installed from TestFlight and runs as the iPad app), the four tabs are a list down the left side: Today, Week, Season, Sessions, Progress, Settings, each word in its own colour. The app opens on Today. Tap a row to go there; tap the row you are already on to come back to its first screen. On a Mac, Command and 1 to 6 choose a row, and Escape is Cancel on every page that has Cancel. At the foot of the list the sync dot says, in words, whether the plan is the same on all devices.",
            "Today, Sessions, Progress and Settings are the pages you know from the iPhone, in a comfortable width. Week and Season are new, and only on iPad and Mac.",
            "Week: the whole week in seven columns, Monday to Sunday, today's column a little different in colour. At the top, the week's number, its phase, Easy week or Test week where that is so, and the time: the time planned, or, once something is done, the time done of the time planned. Previous week, This week and Next week move along. Each session is a card: its sport's colour down the left edge, its name, its length, the green tick when it is done, the red word Missed when you marked it so. Tap a card to open the session. An extra you did sits under a thin line in its column, dotted, with the paler tick; tap it to open it.",
            "Drag a session to another day: once the plan lives in the app, a session still to do can be picked up and dropped on another day's column. A rest day, a done session and a missed one stay where they are. The board says, for eight seconds, what happened, like Long ride moved to Fri 27 Nov, with the button Undo. It is the same change as Change on the session's page with only the day new, so it is in Settings → Changes to the plan, where it can also be undone later. Nothing is dropped by accident: there are no arrow buttons, only the drag.",
            "+ Add at the foot of each day makes a new session on that day (the page New session, with the day already chosen). It needs the plan in the app, like + Session.",
            "Season: every week of the plan up to the race as one bar, side by side. The bar's height is the week's planned time and its colour is its phase, cool early in the season and warm near the race, as on Progress. An easy week is the same colour, pale, and says Easy where there is room; a test week says Test. The week you have chosen has a clear outline, a thin line stands where today is, and the race's flag with its name and date stands at the right. Tap a bar to choose that week: the week board for it sits right under the bars, and Week shows the same week.",
            "Under the board, Phases lists each phase as a row: its colour, its name, its first and last day, how many weeks and how many hours.",
            "Season and Week only show and move. They never change a session's figures, and they suggest nothing."
        ]),
        Part(id: "Missed, Move, Swap", body: [
            "Missed writes the missed mark and an optional note. You can still log the session later if you did it after all.",
            "Move changes only the day. +1, beside the heading, puts it on tomorrow in one tap. In Excel the plan totals by week number and sport, never by date, so a moved session keeps its place in every figure; in the app it keeps its place, its photographs and its move history.",
            "Swap exchanges two sessions' days. Only sessions still to do are offered, nearest first — a done session is never swapped by accident."
        ]),
        Part(id: "Changing the plan", body: [
            "You can change the plan only once it lives in this app. Until then, change it in Excel.",
            "To change a session: open it and tap Change. The page Change session has Day, Sport, What you do, Length in minutes, Zone or effort, Purpose and Key session, with Cancel and Save. The session keeps its photographs, its place in the Training calendar and its move history.",
            "To make a new one: Sessions tab → + Session. It opens the page New session.",
            "To take one out: Change → the red button Take out of the plan.",
            "Settings → Changes to the plan lists every change, newest first, with Before and Now. Tap Undo to undo one; it asks first. What you logged since stays. A change that is undone stays in the list, marked Undone. Only the newest change to a session can be undone; an older one says Changed again since.",
            "Thursday rides: Settings → Thursday rides offers one easy ride each Thursday, beside the easy run, from the next Monday to the race. The page lists every ride and, for each week, its time before → after in hours and minutes. Nothing is added until you tap Add 29 rides (the number is the real count). Cancel closes the page before; Done closes it after, with a green line: 29 rides added. Undo them under Changes to the plan. Afterwards each ride is an ordinary session: change it, move it or take it out like any other. A Thursday that already has its ride is skipped; when all are there the page says These rides are already in your plan. If adding fails, a red line says so and nothing is changed. The page can only be opened once the plan lives in this app.",
            "How long: 45 minutes in Base 2; growing from 50 to 60 minutes through Base 3; 60 in Build; 45 in Peak. In an easy week, a test week and the taper it is a 30-minute easy spin. There is none in the race-practice weeks and none in race week.",
            "On iPad and Mac, dragging a session to another day on Week or Season is a change too, with Undo for eight seconds and a line in Changes to the plan.",
            "The app changes the plan only when you tell it to."
        ]),
        Part(id: "Extra workouts", body: [
            "Walks, yoga, rowing, breathing, a run the plan did not ask for: these go on their own list (in Excel, the Extras sheet), never into the plan, so the plan's own compliance arithmetic stays honest. Counts as training is yours to set — a swim, bike, run, strength or rowing counts unless you say otherwise; a walk or a meditation does not unless you say it does.",
            "Add one with the small Extra workout pill at the end of the Tomorrow line on Today. Each kind carries its own hand-drawn mark in its own colour. They show on Today and in the week strip, dotted, on the Sessions tab under Done and All, and all of them together under Settings → Extra workouts.",
            "The round pen on its card opens it for changing — in the Sessions list or on its own screen. Only the boxes you alter are changed, so correcting the length leaves everything else exactly as it was, and emptying a box empties it. While the plan is in Excel, it reads as waiting to sync until it reaches Dropbox, like anything else you log. Once the plan lives in the app, it is saved at once.",
            "An extra workout gets the same row, How hard was it? 1 to 10, on its own page. It counts in Load on Progress whether or not it counts as training — only breathing and meditation are left out.",
            "Photographs follow an extra when you change it, even when you change the day, the activity or the length it is known by."
        ]),
        Part(id: "How your plan is kept safe", body: [
            "While the plan is in Excel: everything you log is saved on the phone first and sent to Dropbox straight away. Until Dropbox has confirmed, it shows as waiting — in Settings and at the top of Today.",
            "Each send starts from the copy that is in Dropbox right now, writes into it, reads the result back to check it, and uploads it against the exact version it started from. If the file changed in between — Excel on the laptop, or anything else that saved it — Dropbox refuses, and the app starts again from the newer copy. Nothing is ever overwritten, and nothing you logged is lost.",
            "A row is checked before it is written into. If the session was changed in Excel into something else, the log is kept waiting with the reason rather than written into the wrong place.",
            "Once the plan lives in the app: there is no sending and no waiting. Everything is saved on the phone the moment you tap. An entry that could not be written stays on the phone with its reason, in Settings.",
            "The app keeps the plan as it was at the start of each day the plan changed, for 30 days, and makes a spreadsheet copy about once a week. The spreadsheet copies are described in Where the plan lives. The iPhone's own backup covers the plan as well. On an iPad and a Mac the plan is also in your iCloud, and each device keeps its own safety copies, made on that device. The copy each device kept before it first met iCloud is under Settings → iCloud → Copy from before iCloud; see The same plan on all your devices.",
            "Settings → Safety copies is one row, and it opens a page that lists the days, newest first. A copy is made at the start of each day the plan changes, not every day. Each row gives the day, then what its copy holds, like 372 sessions · 83 done · 4 changes so far, and under it the red button Put this copy back. It asks first. If you go on, the plan goes back to how it was at the start of that day, and everything logged or changed from that day on is taken out. The plan as it is now is kept aside first, so even that step can be put right. Afterwards a green line says The plan is back as it was at the start of Mon 23 Nov. A copy that will not open says so in red, and nothing is changed. With none yet the page says: No safety copies yet. The first one is made the next time the plan changes. The page can only be opened once the plan lives in this app."
        ]),
        Part(id: "Photographs", body: [
            "A session or an extra can carry photographs. They live on this phone beside the plan, never inside it — not in the workbook, and not in the spreadsheet copies — and the iPhone's own backup covers the pictures. Settings → Photos saves them all out, and brings in the web app's export. Photographs are not sent through iCloud: they stay on the device where they were taken.",
            "Adding one happens behind the pen: open the form and press Add photo, which asks whether to take one now or pick from your photos. A picture is kept the moment you add it — there is nothing to save, and the Save button only ever writes the boxes you changed. In the Sessions list, the first three of a session's pictures sit in the corner of its row, beside the pen.",
            "A photograph is shown against the session it was taken against: the row of the sheet, or failing that the same day and the same sport, so that a line inserted in Excel — which shifts every row below it — does not hide your pictures. A session that lives in the app keeps its own name for good, so changing or moving it never loses its pictures. The sport always has to agree; a row that has become another kind of session is a different session. Nothing is ever dropped: every picture is counted and exported whether or not it can be placed."
        ]),
        Part(id: "Before you train", body: [
            "Today opens with what the night left behind: how long you slept, your resting heart rate and your HRV — on one row, each with how far it sits from your own normal in brackets: green the good way, red the other, grey when it is as usual. A resting heart rate means nothing against anybody else's, and one morning means little against one other morning. Your normal is the average of up to fourteen days before the morning shown, one reading a day, and there is none until four days are there to make it — until then the brackets say when it will come. Settings → Apple Health → What Health hands over shows your normal and how many days it stands on. It is all read again every time you open the app. Garmin passes sleep to Apple Health but apparently not HRV, so that one may never appear.",
            "No score is made out of them. They are there to be read before you train, which is the one question the rest of this app can only answer afterwards. They appear when Apple Health has them; it asks once for permission. On an iPad or a Mac there is no Health: your iPhone puts the numbers in iCloud and they are shown there in the same row, with a small grey line under it, from iPhone, as of 07:12 (or yesterday 07:12 once they are more than 18 hours old, and then paler)."
        ]),
        Part(id: "Morning numbers from Garmin", body: [
            "Your Garmin watch knows what Apple Health does not hand over: overnight HRV, sleep, Body Battery and stress. Settings → Garmin says Garmin · not connected or Garmin · connected. Open it: make a personal key once in your Garmin account at connect.garmin.com, paste it into the field Paste your Garmin key, and tap Save (Cancel closes the page). While it asks Garmin, the button says Checking…. A key Garmin does not accept says so in red, and nothing is saved.",
            "The key is kept in this device's own Keychain and nowhere else: not in the plan, not in iCloud, not in a copy, and it is never shown again, only as dots. It stays on this device only, so an iPad or a Mac that should show the numbers needs the key pasted there too. Once saved, the page says Connected and when the numbers were last read, with two buttons: Read again now, and Remove the key (it asks first, Remove the key or Keep it; Today then stops showing Garmin numbers, and you can paste a key again at any time).",
            "Today then has a second line under the morning line: HRV 64 (+3) · Sleep 7 h 20 · Resting 47 (−1) · Body Battery 71 (invented numbers). HRV and Resting carry how far they sit from your own normal in brackets, as the Health line does: green the good way, red the other, grey when it is as usual, and until your normal exists the brackets say when it will, like normal in 3 days. Your normal is the average of up to fourteen earlier days, and there is none until four days are there. Sleep and Body Battery carry no bracket.",
            "Under the line a small dot says where the numbers are from, with words: green, Garmin · this morning, read 07:12; grey, Garmin · older numbers from the day they belong to. When Garmin has not yet received the night from your watch, the older numbers stay and the dot is grey. Between midnight and four in the morning the night that last ended counts as last night.",
            "Tap the line for the plate, Garmin, this morning: HRV overnight in ms (with Garmin's own balanced range when it gives one), Sleep last night, Resting heart rate in bpm, Body Battery on waking and Stress yesterday, each with your normal and how many days it stands on, or none yet and Garmin has not given this one yet. It also says when your watch last sent its numbers to Garmin. Done closes it (Escape on a Mac).",
            "The app reads Garmin when Today opens, at most once in half an hour, and Read again now asks at once. It only reads: a few small requests for your own numbers, nothing is written to Garmin. When Garmin gives a number the Health line also had (sleep, HRV, resting), the Garmin one is shown and the Health one is left out, so one thing is never two numbers side by side.",
            "These numbers are shown only. They never change your plan, and nothing in the app reacts to them: no advice, no score."
        ]),
        Part(id: "Progress", body: [
            "The flag beside the weeks to go holds what the race is — distances, where, and the day — and under it the phases of the season: each one's colour, the name your sheet gives it, how many weeks it lasts and how many sessions it holds. Each block of the bar carries that number too, where it is wide enough to hold it. Under the bar, how many of the phase you are in are behind you.",
            "Nothing here is read from a Progress sheet in Excel — its cells are formulas that carry Excel's last answer, and the app never recalculates them. Every figure is worked out from the session rows each time the screen opens, and none of it is stored.",
            "Fitness and freshness: each session is turned into what it cost — an hour at your threshold heart rate is 100, an easy hour far less, because hours alone cannot tell an easy week from a hard one. Six weeks of those costs is fitness, the last week is fatigue, and the difference is how fresh you are: under zero is carrying work, over zero is rested. It uses your heart rate where you recorded it, your effort where you did not, and the zone the plan asked for failing both.",
            "The road: weeks to the race, the phases as one bar with today marked on it — each phase in its own colour, cool early in the season and warm near the race, today's at full strength and the weeks ahead faint — sessions done, hours banked against hours due. Is it working: distance per heartbeat, the first half of your logged easy sessions against the last, one sport at a time — it says nothing until eight sessions of a sport carry a distance, a time and a heart rate. Twelve weeks: the hours you did against the line the plan asked for, counting only weeks that are over — a week still being lived would show the sessions left in it as hours missed. Then what was kept: completed, missed, unanswered; the run you are on; which sport runs behind; missed against moved.",
            "Load sits directly under Fitness and freshness. Three figures: this week so far, last week, and your usual week, which is the average of the four finished weeks before this one. Under them, eight weekly bars. Load is minutes times how hard it was (1 to 10): a 60-minute run at 5 counts 300.",
            "A solid purple bar is what you did in the plan. A dotted purple bar is outside the plan — dotted means outside the plan here as on Today: your extra workouts, and workouts in Apple Health that are in neither the plan nor your extras, such as a hike or the gym, if they are at least 10 minutes long. Breathing and meditation are left out. Counts as training does not decide this: a hike is load either way.",
            "Where you gave no number, the app uses the plan's zone: Z1 counts 2, Z2 counts 3, Z3 counts 5, Z4 counts 7, Z5 counts 9. Where there is no zone either, it counts 3, which is easy. The card says how many were guessed. Health workouts of the last 14 days without a number are listed there with a How hard? button; your answer is kept on the phone.",
            "Mornings: a row of fourteen small bars showing how you felt each morning. Taller means better. A gap means you did not answer.",
            "Progress only shows. It suggests nothing and changes nothing in the plan. It counts the same whether the plan is in Excel or in the app. Sleep is shown and never leads to advice."
        ]),
        Part(id: "Your zones", body: [
            "A session's Z2 or Z4–Z5 is a pill on its screen. Tap it and the app says what that is for you this season — heart rate always, bike power on a ride once an FTP is entered, the swim paces on a swim — read from the Test Results & Zones sheet of your workbook, from your latest test. The app never works a zone out itself. Once the plan lives in the app, the zones start from the numbers the workbook held on the day it moved, and follow the newest test you enter in the app.",
            "Entering a test: Settings → Your zones has a section, Your tests. The green button Enter a test result comes first. Under it are the tests that have numbers, newest first. Then one card, Still to come, lists the tests the plan has but that have no numbers yet.",
            "The page has one row for each box: Threshold pulse, Bike power (FTP), Swim pace per 100 m (minutes and seconds, like 1:50), Weight, First day, Last day and Notes. Leave a box empty for not tested this time, but give at least one number. The last day cannot be before the first. The ranges are a pulse of 80 to 220, FTP of 50 to 500 W, a swim pace of 1:00 to 4:00 and a weight of 35 to 150 kg.",
            "Same as the last test fills the four numbers and leaves the days and the notes alone. Cancel closes the page; Save keeps the test. Save never greys out: if something is missing, a red line above it says what. A grey line says which test the entry becomes. It fills the next test the plan has waiting for numbers, like Saves as Test 3. If none is waiting, it becomes a new test.",
            "The zones follow the newest numbers at once. The app stores what you enter and does not judge it. Before the plan lives in the app, a test is entered in Excel as before.",
            "The whole sheet, the current numbers and the words it uses, is under Settings → Your zones.",
            "The numbers come from your latest test row. The zone tables are your sheet's own formulas: if another program saves the file without the answers Excel worked out, the tables show a dash until you open the plan in Excel once and save it. A spreadsheet copy made by the app keeps the zones sheet as it was."
        ]),
        Part(id: "In your calendar", body: [
            "Settings → Calendar → Put them in writes every session from today to the end of the plan into a calendar called Training: at six in the morning (or the hour you set), each as long as it is planned, one after the other on a day with two. Each is headed by the sport and its length and nothing else — Run 35, Swim 40, Bike 2h30min — with the session's own words in the notes. A rest day is an all-day event. The events float, so six stays six wherever the phone is.",
            "Or choose All day, and every session becomes an all-day event on its own day instead, still headed by the sport and its length.",
            "The app keeps them right: a moved session moves its event, a changed session rewrites it, a session that disappears or is taken out of the plan takes its event with it, and a new session made in the app gets one. Days already behind are left as they were. The Training calendar is the app's own — from today onwards it holds the plan and nothing else — and Take them out removes it. The Training calendar is written by your iPhone only. On an iPad or a Mac, Settings → Calendar says Kept by your iPhone, and the calendar appears in Calendar there through iCloud."
        ]),
        Part(id: "Sending a session", body: [
            "The share button at the top of a session offers the whole session — the brief, for a training partner — and, once it is done, what you did: one sentence for the person at home, with the time and the distance. Photos on the session go along. Heart rate and effort never do."
        ]),
        Part(id: "Speaking instead of typing", body: [
            "Any box takes dictation: the microphone on the keyboard."
        ]),
        Part(id: "What this app does not do", body: [
            "It never changes your plan by itself. Everything in the plan is written because you tapped something.",
            "It does not follow your Excel file once the plan lives in the app. The file stays as it was; the app's spreadsheet copies are the way to have a workbook again.",
            "It gives no advice. How you feel, how hard it was, your sleep and your load are shown to you and that is all. The grey lines about eating, drinking and protein are common habits of sport, the same for everyone.",
            "It does not put workouts on your watch. The Garmin Connect card only lists the steps, so that you can build the workout there yourself.",
            "It sends nothing anywhere but your own iCloud (the plan, your answers, and the iPhone's Health numbers) and, only when you have saved a key, it reads your own numbers from Garmin. Nothing goes to your watch, and nothing about you goes to anyone else.",
            "Garmin's numbers, Season, Week and the sync dot show things. None of them changes your plan or says what you should do.",
            "It is not a doctor. For anything about your health, ask one."
        ]),
        Part(id: "Signs in this app", body: [
            "Fixed meanings, everywhere\n• Green tick: done, and nothing else.\n• Red: missed, taken away, or a warning.\n• Moon: a rest day.",
            "The four tabs\n• Each tab has its own colour: Today green, Sessions blue, Progress purple, Settings grey. The tab you are on fills its whole quarter of the bar.\n• The little swim, bike, run and strength marks on the tabs are decoration only. They do not mean swim, bike, run or strength there.",
            "Colours of the sports, everywhere\n• Blue is swim. Yellow is bike (and brick). Light green is run. Orange is strength. Teal is rowing. Violet is mobility and yoga. Red is race. Grey-blue is rest, and also meditation, breathing, walks, hikes and skiing. Light blue-green is anything else.\n• A round badge in a sport's colour, with its own hand-drawn mark, says which sport a session is.",
            "Today, the week card\n• Solid block: recorded.\n• Lighter block of the same colour: still to do.\n• Hatched block (diagonal lines): marked missed.\n• Dotted block: an extra you did outside the plan.\n• Small green tick on a block: that session is recorded. A paler tick: that extra is done.\n• Moon in a day's column: a rest day.\n• Green disc behind a day letter: today.\n• Thin line under the hours: how much of the week's planned time is recorded.\n• Little notch on that line: where the week should be by the end of today.\n• Row of small green blocks under it: extra time that counts as training, one block a quarter of an hour.\n• Amber block in that row: one full hour of it.",
            "Today, the morning\n• Five faces, Bad, Tired, OK, Good, Great: tap one to say how you feel. Once a day.\n• Feeling good (or the word you chose) on the morning line: your answer. Tap it to change it.\n• Green bracket after a figure: better than your own normal of the last two weeks. Red bracket: worse. Grey bracket: about as usual, or not enough days yet to know your normal.",
            "Today, the cards\n• Green circle with a white tick and a green frame: the session is recorded.\n• Red frame and the red word Missed: you marked it missed.\n• No frame: still to come.\n• Green words Waiting to sync: logged on this phone, not yet written into your plan in Dropbox. You only see them while the plan is in Excel; once it lives in the app, nothing waits.\n• Grey pill with a camera and a number: how many photos the session has.\n• Pill with a › at the end: tap it to see what that zone means.\n• Pale blue ground under Tomorrow: everything on it is tomorrow's.\n• Moon on a grey badge: a rest day, with nothing to do.",
            "Today, top and warnings\n• Orange TEST COPY: the app is working on a test copy of the plan, not the real one.\n• Sending… or a number waiting, in a grey outline: logging is on its way to Dropbox. (Only while the plan is in Excel.)\n• Card with a red frame and a red button: logging has waited more than a day. Press the button to send it now. (Only while the plan is in Excel.)",
            "A session's screen\n• Solid green button with a tick and the time: done, exactly as planned.\n• Row of numbers 1 to 10 (How hard was it?): 1 very easy, 7 hard, 10 all out. One tap saves it.\n• Green outlined buttons: log details, or log it after all.\n• Small heart on a button: Apple Health has numbers from your watch for this session.\n• Red outlined button: Missed.\n• Blue: changing the plan — Move, Change, + Session.\n• Grey line under the figures: a general habit about eating, drinking or protein. Only text; it asks nothing.\n• Show the steps / Hide the steps: opens and closes the Garmin steps on the session's own page. Nothing goes to the watch.\n• Share mark, top right: send this session, or what you did, to somebody.\n• Round grey pen: correct the figures you logged — what you did.\n• Button Change: alter what is planned — the day, the sport, the length. Only once the plan lives in the app.\n• Red button Take out of the plan, at the bottom of Change session: it takes the session out. You can undo it.\n• Green edge round a box in a form: you changed that box (also on Change session).",
            "Sessions tab\n• Four numbers, Upcoming, Done, Missed and All: the one you chose is in a blue box.\n• Bar under them: solid blue is recorded, hatched blue is missed, light blue is still to come.\n• + Session: make a new session in the plan. Only once the plan lives in the app.",
            "Moving the plan in, and where it lives\n• Green word same: the two figures agree.\n• Red word differs: the two figures are not the same. The plan does not move while anything differs.\n• Everything matches.: every figure and every session is the same on both sides.\n• Looked odd in the file: a value that looks strange. It is shown, not mended.\n• Lives in this app, in Settings → Your plan: the plan is kept in the app and Excel no longer follows it.\n• Red button Go back to Excel: writes the plan as it is now into your Excel file and makes Excel the plan's home again. For three weeks only.\n• Grey Undone in Changes to the plan: that change was undone. It stays in the list.\n• Before and Now in that list: the plan as it was, and as it is now.\n• Red button Put this copy back, in Safety copies: the plan goes back to the start of that day. The plan as it is now is kept aside first.\n• Red line above Save on the test page, or at the top of Safety copies or Thursday rides: what is missing or what went wrong.\n• Grey line above Save on the test page: which test the entry becomes.\n• Green line after Put this copy back or Add rides: it is done.\n• Before → after in Thursday rides: a week's time now, and with the rides added.",
            "Progress tab\n• Big purple number and flag: time to the race. Tap the flag to see what the race is.\n• Coloured blocks in the road: the phases of your build, cool early and warm near the race. The strongest block is where you are now, the ones behind you a little lighter, the ones ahead fainter.\n• Green arrow up, red arrow down, grey arrow across: you travel further per heartbeat, less, or the same.\n• Purple line with pale fill: your fitness. Red dashed line: your fatigue.\n• Solid purple bar in Load: load from sessions in the plan.\n• Dotted purple bar in Load: load outside the plan.\n• How hard? button: a Health workout with no number yet. Tap it to give one.\n• Small Mornings bars: how you felt each morning. Taller is better. A gap is no answer.\n• Purple bars in the hours chart: hours done each week. The line over them: hours the plan asked for.\n• Red words like plan 30% +5: your hours have drifted five points or more from the plan's mix.\n• Red sentence about sessions never recorded: they are behind you and you did not say done or missed.",
            "The sync dot (Settings → iCloud, the foot of the side list on iPad and Mac, and the page an iPad or Mac shows before the plan has arrived)\n• It always comes with its words; the dot alone means nothing.\n• Green dot, Same on all devices: the plan here is the same as on your other devices. It is a dot, not a tick: the green tick still means done and nothing else.\n• Amber dot, On its way: the plan is travelling between your devices. It is a dot; the amber block under the week card still means an hour of extra time.\n• Grey dot, iCloud is off: this device is not signed in to iCloud, so its plan is not shared.\n• Red dot: a problem, and the words say which. Nothing was changed on this device because of it.\n• Plan from your iPhone · 214 sessions, beside a green dot: the plan has arrived here and opens in a moment (invented numbers).",
            "On iPad and Mac\n• Side list: Today green, Week blue, Season amber-brown, Sessions blue, Progress purple, Settings grey. The row you are on has a pale box. Week and Sessions share their blue because both are about the plan.\n• Season bars: a taller bar is more planned time. The colour is the phase, cool early and warm near the race. A pale bar is an easy week and says Easy where there is room; Test is a test week. Pale means an easy week here; on the week card on Today, a lighter block means still to do.\n• Clear outline round a bar: the week you chose. Thin dark line: where today is. Flag at the right: the race, with its name and date.\n• Green day name on the week board: today. Coloured line round a column while you drag: where the session will land.\n• Dotted card under a thin line in a day: an extra you did, with the paler tick, as on Today.\n• Undo, beside the line that says a session moved: it lasts eight seconds.",
            "Morning numbers from Garmin\n• The Garmin line under the morning line: HRV, Sleep, Resting, Body Battery. Brackets as on the Health line: green the good way, red the other, grey when it is as usual or when your normal is not there yet.\n• Green dot, Garmin · this morning, read 07:12: the numbers are from this morning. Grey dot, Garmin · older numbers from a day: they are older. The words are always beside the dot.\n• Grey line, from iPhone, as of 07:12: these are your iPhone's Health numbers, shown on an iPad or a Mac, and when the iPhone read them. Paler once they are more than 18 hours old.\n• Green word Connected and a row of dots in Settings → Garmin: a key is saved on this device. The dots are not the key.\n• Red words under the field or the buttons: Garmin did not accept the key, or could not be reached.",
            "Buttons everywhere\n• Full green button: the main step on that screen.\n• Green outlined button: an ordinary action.\n• Red outlined button: it takes something away (disconnect, discard, stop, delete, take out of the plan, go back to Excel, put a safety copy back).\n• Grey outlined button: a quiet one, usually a correction.\n• Red words under a button: something went wrong.\n• › at the end of a row: opens another screen."
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
        Release(version: "2.2 (76)", date: "25 November 2026", headline: "iPad and Mac, one plan everywhere, Garmin in the morning", items: [
            "On iPad and Mac. The app now has its own look on a wide screen. The bar along the bottom becomes a list down the left side: Today, Week, Season, Sessions, Progress, Settings, each word in its own colour. It opens on Today. Tap the row you are already on to come back to its first screen. On a Mac, Command and 1 to 6 choose a row, and Escape is Cancel. The iPhone looks as before.",
            "New on iPad and Mac: Week. The whole week in seven columns, Monday to Sunday. At the top: the week's number, its phase, Easy week or Test week where that is so, and the time planned (or the time done of the time planned). Previous week, This week and Next week move along. Each session is a card with its sport's colour down the left edge, its name, its length, the green tick when it is done and the red word Missed when you marked it. Tap a card to open the session. An extra you did sits under a thin line in its column, dotted, with the paler tick.",
            "New: drag a session to another day. Once the plan lives in the app, a session still to do can be dragged onto another day's column. The board says what happened for eight seconds, like Long ride moved to Fri 27 Nov, with an Undo button. It is the same change as Change on the session's page with only the day new, so it also appears in Changes to the plan. A rest day, a done session and a missed one are not moved. There are no arrow buttons, only the drag.",
            "New: + Add at the foot of each day makes a new session on that day.",
            "New on iPad and Mac: Season. Every week of the plan up to the race as one bar. The bar's height is the planned time and its colour is the phase, cool early and warm near the race. An easy week is pale and says Easy where there is room; a test week says Test. The week you chose has an outline, a thin line stands at today, and the race's flag with its name and date stands at the right. Tap a bar to choose that week: its week board sits under the bars, and Week shows the same week. Under it, Phases lists each phase with its colour, its first and last day, its weeks and its hours.",
            "The same plan everywhere. Your plan, everything you log and change, and your answers to How do you feel? and How hard was it? are now the same on your iPhone, your iPad and your Mac. They travel through your own iCloud, in a folder of this app, and nowhere else. Each device keeps its own full copy and works without internet; they meet when you open the app, a moment after a change, and about every half minute while it is open.",
            "When two devices changed things while they were apart, they are joined and nothing you logged is lost. A session's plan side (day, sport, words, length) and its log side (what you recorded) each come from the device that changed it last, so a change of plan on the iPad and a log on the iPhone both stay. A session is taken out only on purpose, and a log made later brings it back.",
            "New: Settings → iCloud, the first row under Your plan. It shows the dot with its words: green, Same on all devices; amber, On its way; grey, iCloud is off; red, a problem, and the words say which. Then when the devices last met, the button Sync now, Your devices (each iPhone, iPad and Mac with when it was last seen and its version), what is shared, and Copy from before iCloud. The same dot with its words sits at the foot of the side list on iPad and Mac.",
            "New: an iPad or a Mac that opens the app for the first time has no Excel, no Dropbox and nothing to choose. Today says in one line, beside a dot, what it is waiting for: Bringing your plan from iCloud…, or that the plan lives on your iPhone and you should open the app there once, or that it is still in Excel and where to move it in, or how to sign in to iCloud. When the plan arrives it says Plan from your iPhone with a count and the time of the last change, and opens by itself.",
            "New: on an iPhone that is still on Excel, if your iCloud already holds a plan from another device, the page The plan moves in offers the green button Use the plan from iCloud instead of a second import. Anything still waiting on the iPhone is written into that plan. Your Excel file is not changed.",
            "New: two different plans. If your iCloud holds a plan from a second, separate move into the app, the app does not join them. Settings → iCloud shows both side by side with their sessions, what is done and the last change, and you choose Use this one. The other is kept as a file.",
            "New: if a device's clock is behind, the iCloud page says so in red, so that the newest change always wins. A device running an older Triathlon than the plan says Update Triathlon on this device and changes nothing.",
            "Changed: Settings shows what belongs to each device. On an iPad or a Mac, Your plan says Lives in this app and in iCloud, or Not on this iPad yet while the plan is on its way. Calendar says Kept by your iPhone. Apple Health says From your iPhone on a Mac. Dropbox and its copy are for the iPhone only. Going back to Excel is closed once an iPad or a Mac uses the plan; a spreadsheet copy is then the way out.",
            "Morning numbers from Garmin. Settings → Garmin: make a personal key once in your Garmin account at connect.garmin.com, paste it into Paste your Garmin key and tap Save (Cancel closes the page). The page then says Connected, when the numbers were last read, and has the buttons Read again now and Remove the key (it asks first). The key is kept in this device's own Keychain, shown only as dots, and is never sent to iCloud or kept in a copy. An iPad or a Mac that should show the numbers needs the key pasted there too.",
            "New on Today: a second morning line with Garmin's numbers, like HRV 64 (+3) · Sleep 7 h 20 · Resting 47 (−1) · Body Battery 71 (invented numbers). HRV and Resting carry how far they sit from your own normal in brackets: green the good way, red the other, grey when it is as usual, or the day your normal will be there. Under it a dot with its words: green, Garmin · this morning, read 07:12; grey, Garmin · older numbers from a day.",
            "New: tap that line for a plate, Garmin, this morning: HRV overnight with Garmin's balanced range, Sleep last night, Resting heart rate, Body Battery on waking and Stress yesterday, each with your normal and how many days it stands on, and when your watch last sent its numbers to Garmin. Done closes it. Where Garmin has a number that Apple Health also has (sleep, HRV, resting), the Garmin one is shown and the Health one is left out, so one thing is never two numbers side by side.",
            "These Garmin numbers are shown only. They never change your plan, and nothing reacts to them: no advice, no score. The app reads them when Today opens, at most once in half an hour; Read again now asks at once. It only reads, and writes nothing to Garmin.",
            "Changed on iPad and Mac: the Health numbers are the iPhone's, put in iCloud by the iPhone. They are shown in the same row with a small grey line under it, from iPhone, as of 07:12 (yesterday 07:12 once they are more than 18 hours old, and then paler).",
            "Good to know: the plan has to live in the app on your iPhone first. Until you have moved it in (Settings → Your plan → Move the plan into this app), your iPad and Mac have nothing to fetch. The first time an iPad or a Mac opens the app it waits for the plan, then opens it by itself.",
            "Good to know: what stays on the iPhone. Dropbox and its copy of the plan, the Training calendar (it appears in Calendar on your iPad and Mac through iCloud), and Apple Health. Photographs, the Garmin key and the safety copies stay on the device where they were made. Each device saves its spreadsheet copies in its own Files.",
            "Good to know: nothing is sent anywhere but your own iCloud, and, if you saved a key, from Garmin to your device. Nothing goes to your watch, and the app still says nothing medical.",
            "Good to know: the way back. Every device keeps the plan it had before it first met iCloud, for good: Settings → iCloud → Copy from before iCloud, with a Share button. Safety copies and spreadsheet copies work as before.",
            "Unchanged: logging, Missed, Move, Swap, extras, Progress, Load, zones, tests, Thursday rides, the Training calendar and photographs. Your Excel file is not touched.",
            "New in How this works: On iPad and Mac, The same plan on all your devices and Morning numbers from Garmin are new parts; What this app is, Where the plan lives, Today, Changing the plan, How your plan is kept safe, Photographs, Before you train, In your calendar and What this app does not do say what changed. Signs in this app has the new dots and bars, each with its words."
        ]),
        Release(version: "2.1 (75)", date: "25 November 2026", headline: "Enter a test, safety copies, Thursday rides", items: [
            "New: Enter a test result. Settings → Your zones now lists every test, newest first, with the green button Enter a test result. The main button comes first. Under it are the tests that have numbers, newest first, and one card, Still to come, for the plan's tests without numbers yet. The page has Threshold pulse, Bike power (FTP), Swim pace per 100 m (minutes and seconds, like 1:50), Weight, First day, Last day and Notes. Same as the last test fills the four numbers and leaves days and notes alone. Cancel closes; Save keeps it. Your zones follow the newest numbers at once.",
            "Save never greys out. If something is missing or out of range, a red line above it says what. An empty box means not tested this time; at least one number is needed; the last day cannot be before the first. Ranges: pulse 80 to 220, FTP 50 to 500 W, swim pace 1:00 to 4:00, weight 35 to 150 kg. A grey line says which test the entry becomes: the next one the plan has waiting for numbers, like Saves as Test 3, or a new test if none is waiting.",
            "Changed: Settings → Safety copies is now one row, and it opens the page. A copy is made at the start of each day the plan changes, not every day, and kept for 30 days. Each row gives the day and what its copy holds, like 372 sessions · 83 done · 4 changes so far. With none yet the page says No safety copies yet.",
            "Under each row, a red button, Put this copy back, asks first. The plan goes back to how it was at the start of that day, and everything logged or changed from that day on is taken out. The plan as it is now is kept aside first, so even this step can be put right. Afterwards a green line says The plan is back as it was at the start of that day.",
            "New: Settings → Thursday rides. One easy ride each Thursday, beside the easy run, from the next Monday to the race. 45 minutes in Base 2; growing from 50 to 60 minutes through Base 3; 60 in Build; 45 in Peak. A 30-minute easy spin in easy weeks, test weeks and the taper. None in the race-practice weeks and none in race week.",
            "The page lists every ride, and for each week its time before → after in hours and minutes. Nothing is added until you tap Add 29 rides (the number is the real count). Cancel closes it before; Done after, with a green line: 29 rides added. Undo them under Changes to the plan. A Thursday that already has its ride is skipped; when all are there the page says These rides are already in your plan. If adding fails, a red line says so and nothing is changed. The rides are ordinary sessions afterwards.",
            "New on a session's page: a session over 90 minutes that is still to do carries one grey line about eating and drinking on the way (about 30–60 g of carbohydrate an hour). A strength session, to do or done, carries one about protein afterwards (20–30 g within an hour or two). These are common habits of sport, not medical advice.",
            "New on a session's page: a Garmin card. A run or ride made of repeats, like 3 × 8 min at Z3, carries it while it is still to do. Swims, strength, finished sessions and texts the app cannot read into steps have none. It is one line, Build it like this in Garmin Connect, with a small green button Show the steps (Hide the steps when open). The steps say how to build the workout in Garmin Connect, and Copy the steps copies them as text. Saved there, it stays in your Workouts list: copy it for next week and send it to your watch. The app itself sends nothing to the watch.",
            "Good to know: the test page, the safety copies and the Thursday rides work once the plan lives in the app. The grey lines and the Garmin card show whether the plan is in Excel or in the app.",
            "Unchanged: Today, Sessions, Progress, Load, Apple Health, the Training calendar and photographs. Your Excel file is not touched.",
            "New in How this works: Where the plan lives, Your zones, How your plan is kept safe, Changing the plan, On a session's page and What this app does not do say what is new. Signs in this app has the new marks."
        ]),
        Release(version: "2.0 (74)", date: "25 November 2026", headline: "The plan can live in the app", items: [
            "Big change, and your choice: the plan can now move from the Excel file in Dropbox into this app. Nothing happens until you tap. If you do nothing, the app works as before.",
            "To move it: Settings → Your plan → Move the plan into this app → Start → Take the plan in and count. The app counts the plan as Excel has it and as the app holds it.",
            "Excel and the app, side by side shows both counts for sessions, training, rest days, done, missed, still to come, extra workouts and minutes. Green same: they agree. Red differs: they do not. Month by month shows the same for each month.",
            "Looked odd in the file lists strange things, such as a pace that cannot be. They are taken in as written; correct them later with the pen.",
            "Everything matches. brings the button Make this app the plan's home. Nothing is saved until you tap it. Entries still waiting for Dropbox must be sent first.",
            "After the switch, logging, Missed, Move, Swap, extra workouts and How hard was it? are saved in the app at once, also without internet. Nothing is written into your Excel file any more, and what you change there, the app does not see. Logging follows the same rules as before; it was checked against Excel on the same entries.",
            "Settings → Your plan now says Lives in this app, with the day you moved it. Safety copies: one for each day the plan changed, the newest 30 kept.",
            "Spreadsheet copy: Save a copy now makes a spreadsheet of the plan, to keep or send. The app also makes one about once a week in Files → On My iPhone → Triathlon, and keeps the newest eight. Each is checked against the plan first; one that does not match is never given.",
            "Copy in Dropbox: the app also saves the plan there as a spreadsheet, Triathlon plan from the app, beside your Excel file. It is written a little after each change and never read back. Settings → Your plan → Copy in Dropbox shows when.",
            "Go back to Excel: for three weeks a red button writes the plan into your Excel file in Dropbox and makes Excel the plan's home again. If that file changed in the meantime, the app refuses and does nothing. After three weeks the button goes.",
            "New, once the plan lives in the app: on a session's page, Change opens Change session (Day, Sport, What you do, Length in minutes, Zone or effort, Purpose, Key session; Cancel and Save) with a red Take out of the plan. On the Sessions tab, + Session opens New session.",
            "Settings → Changes to the plan lists every change, newest first, with Before and Now and an Undo button. A change that is undone stays in the list, marked Undone. Only the newest change to a session can be undone; an older one says Changed again since. It never undoes what you logged. A session keeps its photographs, its place in the Training calendar and its move history.",
            "Unchanged: Today, Sessions, Progress, the two questions, Load, Apple Health, the Training calendar and photographs work as before, with the plan in Excel or in the app.",
            "Good to know: a spreadsheet copy does not change after it is made. Until the iPad and Mac versions come, the plan lives on this iPhone only. Your iPhone's own iCloud copy includes it, and so do the safety copies.",
            "Fixed: tapping a tab at the bottom now changes the page at once. It used to slide, and after adding a session the pages could stop half-way between two tabs. Swiping is unchanged.",
            "New: How this works has two new parts, Where the plan lives and Changing the plan. Every other part says what holds before and after the switch. Signs in this app explains the new marks.",
            "Checked before release: the move was rehearsed on a copy of a real plan, every session and every month compared, and a team of reviewers tried to break it. What they found was fixed first: a change is shown only once it is safely saved, a plan that will not open is put back from its newest safety copy, and the Excel file is read once more at the moment you tap the switch.",
            "Coming next, with no dates: the app on iPad and Mac, a morning check with Garmin numbers, suggestions by the rule book, Claude built in, and links to Workout Companion and Magic Morning."
        ]),
        Release(version: "1.2 (73)", date: "24 November 2026", headline: "A new name, how you feel, how hard it was, and your load", items: [
            "New name: AMS Triathlon Training. Under the icon on the home screen it reads Triathlon. It is the same app with the same data, and nothing to set up again. This is the first step of growing the app into one training app. The plan still lives in your Excel file, untouched.",
            "Today asks a morning question, How do you feel? A small card under the green heading shows five faces with a word under each: Bad, Tired, OK, Good, Great. One tap, once a day. After the tap the card is gone until tomorrow, and the morning line shows Feeling good (or the word you chose). Tap that word to change it. The answer is kept on this phone only; it is not written into the plan. Nothing on Today reacts to it: no advice, no score.",
            "After Done, the session asks How hard was it? On the session's own page, where the Done button was, there is now a row of numbers 1 to 10 (1 very easy, 7 hard, 10 all out). One tap saves it into the plan's Effort column, the same box as Effort in Log details, so there is no new column in Excel. If you do not answer, it simply waits on that session: no reminder, no badge. Extra workouts get the same row on their own page.",
            "Progress has a new Load card, directly under Fitness and freshness. It shows three figures: this week so far, last week, and your usual week, which is the average of the four finished weeks before this one. Under them are eight weekly bars.",
            "Load is minutes times how hard it was (1 to 10): a 60-minute run at 5 counts 300. A solid purple bar is sessions in the plan. A dotted purple bar is outside the plan: your extra workouts (all of them except breathing and meditation), and workouts in Apple Health that are in neither the plan nor your extras (hikes, the gym), if they are at least 10 minutes long. Breathing and meditation are left out.",
            "Where no number was given, the app uses the plan's zone (Z1 counts 2, Z2 counts 3, Z3 counts 5, Z4 counts 7, Z5 counts 9), and where there is no zone it counts 3, which is easy. The card says how many were guessed. Health workouts of the last 14 days without a number are listed there with a How hard? button; that answer is kept on the phone.",
            "A row of fourteen small bars, Mornings, shows how you felt each morning. Taller is better. A gap means you did not answer.",
            "The app only shows. It suggests nothing and changes nothing in the plan by itself. Sleep is shown and never leads to advice.",
            "Fixed: a rest day now carries a moon. It used to carry the same tick as done, which was wrong: the tick means done and nothing else.",
            "New in How this works: Signs in this app, every mark and colour and what it means. Also a short part, What this app does not do.",
            "New: a written specification of the whole app is kept with the code.",
            "Tidied: two stray copies of the project file were removed from the code store. Nothing you can see.",
            "Unchanged: your Excel plan and your zones. No new test numbers were entered in November, so the zones stay on the last test until the next one."
        ]),
        Release(version: "1.1 (72)", date: "28 October 2026", headline: "The trend is always there, in brackets", items: [
            "Resting and HRV now always carry their trend in brackets — Resting 48 (−2) — green when it moved the good way, red when the other, grey when it is about as usual. Before, the figure was left out whenever the difference was small, so a quiet morning looked like a missing trend.",
            "Your normal is worked out more carefully. It used to average every reading Health held over the fortnight, this morning's included, so a day Health held twice counted twice and the morning was partly measured against itself. Now each day counts once, the morning shown is held against the days before it, and there is no normal until four days are there to make one — the brackets say \"normal in 2 days\" until then.",
            "Settings → Apple Health → What Health hands over shows your normal beside each reading and how many days it stands on, and says sleep is \"none since 6 pm yesterday\" when Garmin has not handed last night over yet."
        ]),
        Release(version: "1.1 (71)", date: "27 October 2026", headline: "Slept counts the night once", items: [
            "Slept said 10h 40m after a night of about 5h 20m. Apple Health can hold the same night more than once — Garmin handing it over again on a later sync, or the whole night and its phases side by side — and the app added every copy together. A stretch of sleep now counts once however many times Health holds it, and if two devices both recorded the night, the app takes the fuller of the two rather than adding them."
        ]),
        Release(version: "1.1 (70)", date: "27 October 2026", headline: "The morning line is one row, always current — and a Dropbox button", items: [
            "The morning line at the top of Today is a single row now — Slept 7h 24m, Resting 48 −2, HRV 64 +6 — instead of three stacked readings. The small figure after a reading is how far it sits from your own fortnight: green where that way is the good way, grey otherwise, nothing at all when it is as usual.",
            "Today read your night once, the first time the screen appeared, and never again until the app was closed and reopened — so a first read that found nothing left the line missing until a visit to Settings forced a second one. It now reads again every time you open the app.",
            "The line sits right under the heading instead of floating below it.",
            "Without Dropbox, Today used to say Read only in a pill — which looked like a button and gave you nothing to press. It is a real button now: Connect Dropbox, or Choose your plan if Dropbox is connected but no plan is picked, and it takes you to Settings. On your phone it does not show while Dropbox is connected."
        ]),
        Release(version: "1.1 (69)", date: "27 October 2026", headline: "Settings says what Health has for the night", items: [
            "Settings → Apple Health → What Health hands over now lists sleep, resting heart rate and HRV, each as a value or as none in Health. Today hides the morning line when it has nothing to show, which left no way to tell not allowed from nothing there; this is the place to look.",
            "Garmin passes sleep to Apple Health once you switch it on in Garmin Connect (Settings → Connected Apps → Apple Health). It does not appear to pass on HRV, and resting heart rate is not confirmed — so some of the three may stay empty however much you allow."
        ]),
        Release(version: "1.1 (68)", date: "26 October 2026", headline: "Health is asked for the morning numbers", items: [
            "The line at the top of Today never appeared. The app had permission to read your workouts, granted weeks ago, and iOS treats every kind of data as a permission of its own: nothing ever put the question for sleep, resting heart rate and HRV, so the app read a drawer it had never been given the key to and said nothing. It now asks iOS whether the question still needs putting, and puts it — once, for those three."
        ]),
        Release(version: "1.1 (67)", date: "13 October 2026", headline: "What a session cost, and what the night left behind", items: [
            "Progress has a new card, Fitness and freshness. Until now the app counted hours, and hours cannot tell an easy week from a hard one: your plan could be kept to the letter and still not be trained. Each session now costs something — an hour at your threshold heart rate is 100, an easy hour far less — and six weeks of those costs is fitness, the last week is fatigue, and what is left of one after the other says whether you are carrying work or rested.",
            "It is worked out from your own heart rate where you recorded it, your effort where you did not, and the zone the plan asked for failing both; the card says so, because an estimate should admit what it is. Heart rate reads low in water, so a swim costs modestly.",
            "Today opens with last night: how long you slept, your resting heart rate and your HRV, each against your own fortnight rather than anybody else's. Three plain numbers and no invented score. Apple Health will ask once for permission to read them."
        ]),
        Release(version: "1.1 (66)", date: "13 October 2026", headline: "Tomorrow's card carries its pictures too", items: [
            "Today draws photographs on today's sessions, on today's extra workouts and on anything behind you not recorded — but the block for tomorrow was the one list that did not, so a session done early and photographed showed none of them."
        ]),
        Release(version: "1.1 (65)", date: "13 October 2026", headline: "Your photographs come back", items: [
            "Pictures that had stopped being shown are shown again, on Today, in the Sessions list and on the session itself. A photograph remembered the row of the sheet it was taken against, and a row number is not a name: insert a line in Excel and everything below it shifts, so the picture was looking for a row that had become somebody else's. It now falls back on the day and the sport, which shifting rows do not change.",
            "Nothing was ever lost — the pictures were on the phone the whole time, only unfindable."
        ]),
        Release(version: "1.1 (64)", date: "12 October 2026", headline: "A bar under the four counts", items: [
            "Under Upcoming, Done, Missed and All there is now one bar for the whole plan: solid for what is recorded, hatched for what was missed, light for what is still to come — the same three signs the week strip on Today uses, in this tab's blue.",
            "It is counted from the same lists the four numbers are counted from, so the picture and the figures cannot disagree. All is not part of it: that one holds rest days too, which are not sessions anybody does."
        ]),
        Release(version: "1.1 (63)", date: "12 October 2026", headline: "+1 moves it to tomorrow", items: [
            "The Move sheet carries a +1 beside its heading: one tap and the session is on tomorrow, without the date wheel. It is the move made most often.",
            "Move the session is never a dead grey button any more. Pressed before you have picked another day it simply waits, and the line underneath says what it wants.",
            "The Extra workout pill sits level with the word TOMORROW instead of a few points below it."
        ]),
        Release(version: "1.1 (62)", date: "2 October 2026", headline: "Each phase carries its own number", items: [
            "Inside every block of the phase bar, small, the number of sessions that phase holds. The two short blocks near the race — Peak and Taper — have no room for a figure, and their counts are in the list behind the flag.",
            "Today's line used to be drawn straight through the number of the phase you are in. The number now sits to whichever side of the line has more room."
        ]),
        Release(version: "1.1 (61)", date: "2 October 2026", headline: "The weekly figures wait for the week to finish", items: [
            "Twelve weeks counts only weeks that are over. A week still being lived showed every session not yet done as time missed, so a Thursday reading had you behind on hours you still had the weekend to do.",
            "Its columns are the weeks that hold training. Nine empty weeks from before the plan began used to be drawn too, squeezing the real ones into the corner with dates printed under nothing — and the last date was cut off at \"21…\". The dates are spaced evenly now, each under its own column, and the line for the hours asked for is the width of the column it belongs to.",
            "On the road card, all three figures stay on one line; 327h 23m used to fold onto a second while the others did not.",
            "Under the phase you are in: how many of its sessions are behind you. In the list behind the flag, each phase now says how many sessions it holds as well as how many weeks it lasts."
        ]),
        Release(version: "1.1 (60)", date: "2 October 2026", headline: "What Health hands over opens, it does not switch on", items: [
            "That row carries a chevron now, turning to point down when it is open — the sign for showing and hiding a piece of reading. It was a switch for three builds, and a switch means turning something on: sitting directly under In use and Stop, it read as if it controlled Apple Health itself. It never did."
        ]),
        Release(version: "1.1 (59)", date: "2 October 2026", headline: "The open tab fills its whole quarter", items: [
            "The tab you are on is a block of its own colour filling its quarter of the bar — the full width of it, from the top edge down to the bottom of the phone — instead of a small rounded button floating in the middle of it."
        ]),
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
            "Both lists empty while your watch has something means the app is not being given it: Health → your picture → Apps → Triathlon, switch the rows on, then Ask again."
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
