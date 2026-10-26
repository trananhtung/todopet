<p align="center"><img src="docs/icon.png" width="128" alt="TodoPet icon"></p>

<h1 align="center">TodoPet</h1>

<p align="center">
A desktop pet for macOS that lives on top of your Dock, reads your <a href="https://todoist.com">Todoist</a> tasks,
and gets <b>happy when you work</b> and <b>grumpy when you don't</b>.<br>
English · <a href="README.vi.md">Tiếng Việt</a>
</p>

![Moods](docs/moods.png)

## What it does

- **Walks around your screen.** Mochi wanders along the Dock, looks at your cursor, and stops when you hover it. Drag it anywhere and it falls back down.
- **Asks "what are we doing today?"** If today has fewer than **3 tasks** (configurable), it asks you to plan, gently in the morning and more insistently once the planning deadline passes.
- **Reminds you of the right task.** It picks the next task with "eat the frog" ordering (highest priority, then earliest time), nudges you every 45 minutes, and pings you 10 minutes before timed tasks.
- **Has real moods.** It celebrates every completed task (including ones you tick off in the Todoist app), and gets annoyed, then grumpy, when tasks are overdue, nothing moves for hours, or you sit in a distracting app. When grumpy it marches toward your cursor 😤
- **Lets you work with Todoist from the pet.** Click the pet to see today's tasks, complete them, add new ones (Today / Tomorrow / No date, priority, or full Todoist quick-add syntax like `Call Anna 3pm p1 #Work`), move tasks to today or tomorrow, delete tasks (after a confirmation, since Todoist can't restore them), and see your Todoist streak.
- **Has a built-in focus timer.** Start a 25-minute session on a task and the pet puts on a headband and sits quietly in a corner. When time's up it asks if you finished; if you did, it completes the task in Todoist and starts your break.
- **Runs an end-of-day review.** 30 minutes before work ends it shows what you finished and offers to move the rest to tomorrow.
- **Catches distracting websites.** It reads the active tab in Safari, Chrome, Arc, Edge, Brave and other Chromium browsers. Two minutes on YouTube or Facebook during work hours and the pet starts frowning. You choose the sites, and rules like `youtube.com/shorts` match only part of a site.
- **Knows your meetings.** It reads today's events from the macOS Calendar (including Google or Outlook accounts added there). It reminds you 5 minutes before a meeting with a **Join** button, stays quiet during meetings, and doesn't count meeting time as slacking. On a meeting-heavy day it lowers the daily target, roughly one important task per two free hours.
- **Suggests time blocks.** It slots your next tasks into today's free gaps ("10:00–11:00 Write the report"). One click gives the task that time in Todoist, so the pet reminds you right on time.
- **Spots tasks you keep postponing.** When a task has sat on your list for 3+ days, the pet asks whether to split it into 15–30 minute steps (added as Todoist sub-tasks, with step 1 on today's plan) or drop it from the plan. With a Claude API key, **Ask Claude** suggests the steps for you.
- **Speaks English and Vietnamese**, switchable in Settings.

### A pet that lives with your work

![Growth, hunger, accessories and celebrations](docs/life.png)

- **Feed it by finishing tasks.** Every finished task drops a treat into its mouth (+25% fullness). Fullness drains about 7% per work hour, so a lazy day leaves it thin, hungry and rumbling. Each workday you do nothing makes it dirtier, up to 3 levels with flies buzzing around, and each finished task washes one layer off. All of this carries over to the next day.
- **Watch it grow.** Tasks earn XP, and the pet grows from Baby (with little leaves on its head) to Kid, Teen, Grown-up and Master.
- **Surprise celebrations.** Each finished task gets a random dance: jump, spin, back-flip or disco. One in ten is a rare golden treat with a golden pet. Finishing tasks within 30 minutes of each other builds a combo (×2, ×3…) worth more XP, ending in fireworks.
- **Unlock things to wear.** The pet earns a bow, scarf, sunglasses, top hat, crown and grad cap through milestones like your first task, a 3-day streak, a ×3 combo, 25 tasks and a 7-day streak. A sticker book collects every day you finish your whole plan.
- **Mischief that escalates when you slack.** After 10 minutes annoyed, it sighs and stomps. After 10 minutes grumpy, it marches across the screen dragging a sign with the task you're avoiding. Five minutes on YouTube while grumpy and it leaps into the middle of the screen with a (╯°□°)╯︵ ┻━┻. At the end of the day it reports, sulking, how long you spent on distractions. It can also say its lines out loud (off by default).
- **It plays fair.** No mischief during meetings or focus sessions or while you're away. At most one big stunt every 20 minutes. Every stunt has a **Spare me 15'** button, and clicking the pet calls it off. You can turn mischief off in Settings.

| Wardrobe | Mischief |
|---|---|
| ![Wardrobe](docs/wardrobe.png) | ![Sign](docs/sign.png)<br>![Table flip](docs/bubble-block.png) |

| Board | Bubble | Split a task |
|---|---|---|
| ![Board](docs/board-light.png) | ![Bubble](docs/bubble-light.png)<br>![Postponed task](docs/bubble-stuck.png) | ![Split](docs/split.png) |

## Install

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode itself isn't required.

```bash
git clone https://github.com/trananhtung/todopet.git
cd todopet
scripts/build.sh
cp -R build/TodoPet.app /Applications/
open /Applications/TodoPet.app
```

`UNIVERSAL=1 scripts/build.sh` builds for both Apple silicon and Intel.

Want to look around first? Run `open build/TodoPet.app --args --demo` to use sample tasks, no account needed.

## Connect Todoist

1. In Todoist open **Settings → Integrations → Developer** ([direct link](https://app.todoist.com/app/settings/integrations/developer)) and copy your **API token**.
2. Click the pet, paste the token and press **Save & connect**.

The token is stored in your macOS **Keychain** and is only ever sent to `api.todoist.com` (Todoist API v1). After rebuilding the app, macOS may ask once whether TodoPet can read its Keychain item; choose **Always Allow**.

### Permissions macOS will ask for

| Prompt | Why | If you say no |
|---|---|---|
| Calendar | Meetings, free time, time-block suggestions | The board offers an **Allow** button; everything else works |
| "TodoPet wants to control Safari / Chrome…" (once per browser) | Reading the active tab's address for distracting sites | Website detection is off for that browser; app detection still works |

Because the app is ad-hoc signed, macOS may ask again after you rebuild it.

### Splitting tasks with Claude (optional)

Add an Anthropic API key in **Settings → Postponed tasks** ([get one](https://console.anthropic.com/settings/keys)). When you press **Ask Claude** in the split view, the task's title and notes are sent to the Claude API, which returns 3–5 small steps. It uses `claude-opus-5-5` at low effort, with server-side fallback enabled in case a request is declined. Each request costs roughly 1–2 US cents, and you can change the model in Settings. Without a key you can type the steps yourself or start from the quick template.

### Using Todoist from Claude or other AI apps (MCP)

TodoPet talks to Todoist directly with your API token. If you also want to manage tasks by chatting with an AI assistant, connect Todoist's official MCP server at `https://ai.todoist.net/mcp`. In Claude Code that's `claude mcp add --transport http todoist https://ai.todoist.net/mcp`, and in Claude Desktop you add it as a custom connector. Tasks you create there show up on the pet within 3 minutes, or right away when you click it.

## Using it

| Action | What happens |
|---|---|
| Click the pet | Opens the task board |
| Hover a task on the board | ▶︎ focus · ✂️ split · → move · 🗑 delete (asks first; sub-tasks and recurring series go too, and it can't be undone) |
| Drag the pet | Moves it; let go and it drops back to the Dock |
| Hover | It stops walking and blushes |
| Right-click / menu bar icon | Quick menu: add task, focus, hide for 1 hour, quiet for 1 hour, settings |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd> | Opens the board with the add field focused, from any app |

The menu bar shows the mood and today's progress (`😊 2/3`), or the timer during focus (`🍅 18:42`).

## How the mood works

Mochi keeps a 0–100 happiness score, recalculated every 15 seconds. Hover the reason line on the board to see the breakdown.

| Makes it happier | Makes it grumpier |
|---|---|
| +8 per task completed today | −7 per overdue task |
| +30 when today's plan is fully done | −4 per task that's past its time |
| Up to +15 right after you finish something | −12 to −50 when fewer than 3 tasks are planned after the planning deadline |
| +10 during a focus session | Up to −30 when nothing moves for more than 90 minutes |
| Meeting time counts as work | Up to −35 after 2+ minutes in a distracting app or website |
| | −3 per task that keeps getting postponed (up to −9) |
| | Up to −15 when it's hungry (below 30% full) |
| | −5 per level of dirt |

Score ≥ 75 is happy, ≥ 50 is chill, ≥ 30 is annoyed, and anything lower is grumpy. Outside work hours, at night, during meetings, or when you've been away for 10 minutes, it calms down or falls asleep, and it never nags while you're away.

## When it talks

In priority order, at most one bubble at a time:

1. A few minutes before a meeting (even during a focus session), then silence until the meeting ends
2. 10 minutes before, and at the time of, any task with a time
3. Morning greeting with today's plan (or a request to plan) and a summary of the day's meetings and free time
4. "What are our 3 things today?" every 30 minutes after the planning deadline until there are enough tasks
5. A distracting app or website open for more than 2 minutes
6. A task that keeps getting postponed: split it or drop it
7. Hungry: begging for a finished task, at most hourly
8. Mischief while you slack: grumbling, then the sign parade (the table flip comes with rule 5)
9. Overdue tasks, every 90 minutes
10. Once a day, a time block for the next task
11. End-of-day review, then a sulky distraction report if you spent 10+ minutes on distractions
12. A nudge with the next task, every 45 minutes
13. A productivity tip now and then, only when the mood is good

All timings are in **Settings**: daily target, work hours, work days, planning deadline, reminder interval, focus and break length, distracting apps and websites, calendar options, when a task counts as postponed, a custom Todoist filter for "my day" (for example `(today | overdue) & #Work`), pet size, sounds, mischief, spoken lines, focus protection, and open at login.

## Designed not to break your focus

A reminder app that interrupts deep work does more harm than good, so the pet follows what interruption research recommends:

| Rule | Why |
|---|---|
| **Interrupt at a pause.** Non-urgent bubbles wait until you stop typing for a few seconds or switch apps. Meeting and due-time reminders still arrive on time. | Interruptions at task boundaries cause less frustration and faster resumption than mid-task ones (Adamczyk & Bailey 2004; Iqbal & Bailey 2008). |
| **Protect deep work.** After 10 minutes of steady typing in work apps the pet shows 🎧, holds everything non-urgent, and counts the time as progress. No grumpiness, no mischief. | Getting back on track after an interruption is slow and stressful (Mark et al. 2008). |
| **Fewer bubbles.** At least 15 minutes between unsolicited bubbles (configurable), one at a time. | Batched, less frequent notifications improve attention and well-being (Fitz et al. 2019). |
| **Keep still while you type.** The pet stops walking and dampens its movements, and walks again when you pause. | Motion at the edge of vision grabs attention involuntarily (Bartram et al. 2003). |
| **Quiet by default.** Sounds are "important only" (meetings, due times, end of focus, finished tasks) and soft. Ordinary bubbles fade in silently. | Calm technology informs from the periphery and only moves to the center when needed (Weiser & Brown 1996). |
| **Mischief targets slacking, not work.** Antics never fire while you're typing, during meetings or focus sessions, or while you're away. | Nagging someone who's already working only breaks their flow. |

Sounds have three levels in Settings: **Off**, **Important only** (default) and **Everything**.

## Why these features

The behavior is based on well-known productivity practices, kept deliberately simple:

- **Rule of 3**: plan three meaningful outcomes per day instead of an endless list (J.D. Meier, *Getting Results the Agile Way*).
- **Eat the frog**: start with the most important task (Brian Tracy).
- **Implementation intentions**: tasks with a concrete time ("at 2pm I'll…") are more likely to get done (Peter Gollwitzer). The pet reminds you right on time.
- **Pomodoro**: short, timed focus blocks with breaks (Francesco Cirillo).
- **Interruptions are expensive**: getting back on task after a switch takes a long time (Gloria Mark's research), so the pet calls out distracting apps and websites and stays silent during focus and meetings.
- **Time blocking**: giving tasks a slot in the calendar protects time for them; the pet finds the slots between your meetings.
- **Procrastination often means the task is too big or vague**: breaking it into a small, concrete first step makes starting easier, so the pet suggests splitting tasks you keep postponing.
- **Shutdown ritual**: close the day by reviewing and rescheduling (Cal Newport).
- **Emotional feedback**: a character that visibly reacts to your progress makes progress feel rewarding, and slacking slightly uncomfortable.
- **Caring for a pet** (the "Tamagotchi effect", used by apps like Finch): you work partly to keep it fed and clean, and the consequences last across days. Losing something you have motivates more than an equal gain.
- **Variable rewards**: unpredictable celebrations and rare golden treats stay exciting longer than a fixed reward, which is why games use them.

## Privacy

- No analytics and no servers of its own. Network traffic goes to `api.todoist.com`, and to `api.anthropic.com` only when you press **Ask Claude**.
- Distraction detection reads the **name of the frontmost app** and, if a browser is in front, the **address of its active tab**. Addresses stay in memory and are never stored or sent anywhere. No screen recording or accessibility access is needed.
- The calendar is read locally through macOS (EventKit); events never leave your Mac.
- The "postponed tasks" log is just task IDs and dates in the app's local preferences, and the pet's life (fullness, XP, accessories, today's distraction minutes per site) is stored locally the same way.
- Spoken lines use the voices built into macOS, offline.
- Idle detection only reads "seconds since the last input", which needs no permission.

## Development

```bash
scripts/build.sh                                    # build build/TodoPet.app
build/TodoPet.app/Contents/MacOS/TodoPet --selftest   # logic tests (dates, API parsing, moods)
build/TodoPet.app/Contents/MacOS/TodoPet --demo       # run with sample data
TODOPET_ANTIC=parade build/TodoPet.app/Contents/MacOS/TodoPet --demo   # see the mischief (parade or block) right away
build/TodoPet.app/Contents/MacOS/TodoPet --snapshot out/  # render moods, board and bubble to PNG
```

| File | Role |
|---|---|
| `Brain.swift` | Sync, mood, reminder rules, focus timer, actions |
| `MoodEngine.swift` | Pure scoring function behind the mood |
| `TodoService.swift` | Todoist API v1 client and demo service |
| `BrowserWatcher.swift` | Active-tab address via AppleScript, site rules |
| `CalendarWatcher.swift` | EventKit reader, free-time math, time-block suggestions |
| `StuckTracker.swift` | Log of days each task sat on your list |
| `ClaudeClient.swift` | Messages API call that splits a task into steps |
| `PlanningViews.swift` | Calendar card and split-a-task view |
| `PetLife.swift` | Fullness, dirt, XP and stages, combos, accessories, day settlement |
| `Antics.swift` | Mischief types, the dragged sign, spoken lines |
| `LifeViews.swift` | Life bar and wardrobe & achievements view |
| `Calm.swift` | When it's OK to interrupt: typing pauses, deep-work detection, bubble spacing |
| `PetArt.swift` | The pet, drawn in code for every mood |
| `PetWindow.swift` | Floating window, walking, drag and drop |
| `Bubble.swift` / `BoardView.swift` / `SettingsView.swift` | UI |
| `Lines.swift` / `L10n.swift` | Everything the pet says, in English and Vietnamese |

It's plain Swift, SwiftUI and AppKit with no dependencies, built with `swiftc`.

## License

[MIT](LICENSE)
