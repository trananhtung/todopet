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
- **Lets you work with Todoist from the pet.** Click the pet to see today's tasks, complete them, add new ones (Today / Tomorrow / No date, priority, or full Todoist quick-add syntax like `Call Anna 3pm p1 #Work`), move tasks to today or tomorrow, and see your Todoist streak.
- **Has a built-in focus timer.** Start a 25-minute session on a task and the pet puts on a headband and sits quietly in a corner. When time's up it asks if you finished; if you did, it completes the task in Todoist and starts your break.
- **Runs an end-of-day review.** 30 minutes before work ends it shows what you finished and offers to move the rest to tomorrow.
- **Speaks English and Vietnamese**, switchable in Settings.

| Board | Bubble |
|---|---|
| ![Board](docs/board-light.png) | ![Bubble](docs/bubble-light.png) |

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

### Using Todoist from Claude or other AI apps (MCP)

TodoPet talks to Todoist directly with your API token. If you also want to manage tasks by chatting with an AI assistant, connect Todoist's official MCP server at `https://ai.todoist.net/mcp`. In Claude Code that's `claude mcp add --transport http todoist https://ai.todoist.net/mcp`, and in Claude Desktop you add it as a custom connector. Tasks you create there show up on the pet within 3 minutes, or right away when you click it.

## Using it

| Action | What happens |
|---|---|
| Click the pet | Opens the task board |
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
| | Up to −35 after 2+ minutes in a distracting app |

Score ≥ 75 is happy, ≥ 50 is chill, ≥ 30 is annoyed, and anything lower is grumpy. Outside work hours, at night, or when you've been away for 10 minutes, it calms down or falls asleep, and it never nags while you're away.

## When it talks

In priority order, at most one bubble at a time:

1. 10 minutes before, and at the time of, any task with a time
2. Morning greeting with today's plan (or a request to plan)
3. "What are our 3 things today?" every 30 minutes after the planning deadline until there are enough tasks
4. A distracting app open for more than 2 minutes
5. Overdue tasks, every 90 minutes
6. End-of-day review
7. A nudge with the next task, every 45 minutes
8. A productivity tip now and then, only when the mood is good

All timings are in **Settings**: daily target, work hours, work days, planning deadline, reminder interval, focus and break length, distracting apps, a custom Todoist filter for "my day" (for example `(today | overdue) & #Work`), pet size, sounds, and open at login.

## Why these features

The behavior is based on well-known productivity practices, kept deliberately simple:

- **Rule of 3**: plan three meaningful outcomes per day instead of an endless list (J.D. Meier, *Getting Results the Agile Way*).
- **Eat the frog**: start with the most important task (Brian Tracy).
- **Implementation intentions**: tasks with a concrete time ("at 2pm I'll…") are more likely to get done (Peter Gollwitzer). The pet reminds you right on time.
- **Pomodoro**: short, timed focus blocks with breaks (Francesco Cirillo).
- **Interruptions are expensive**: getting back on task after a switch takes a long time (Gloria Mark's research), so the pet calls out distracting apps and stays silent during focus.
- **Shutdown ritual**: close the day by reviewing and rescheduling (Cal Newport).
- **Emotional feedback**: a character that visibly reacts to your progress makes progress feel rewarding, and slacking slightly uncomfortable.

## Privacy

- No analytics and no servers of its own. The only network traffic goes to `api.todoist.com`.
- Distraction detection only reads the **name of the frontmost app** (no screen recording, no accessibility access, no browser tabs).
- Idle detection only reads "seconds since the last input", which needs no permission.

## Development

```bash
scripts/build.sh                                    # build build/TodoPet.app
build/TodoPet.app/Contents/MacOS/TodoPet --selftest   # logic tests (dates, API parsing, moods)
build/TodoPet.app/Contents/MacOS/TodoPet --demo       # run with sample data
build/TodoPet.app/Contents/MacOS/TodoPet --snapshot out/  # render moods, board and bubble to PNG
```

| File | Role |
|---|---|
| `Brain.swift` | Sync, mood, reminder rules, focus timer, actions |
| `MoodEngine.swift` | Pure scoring function behind the mood |
| `TodoService.swift` | Todoist API v1 client and demo service |
| `PetArt.swift` | The pet, drawn in code for every mood |
| `PetWindow.swift` | Floating window, walking, drag and drop |
| `Bubble.swift` / `BoardView.swift` / `SettingsView.swift` | UI |
| `Lines.swift` / `L10n.swift` | Everything the pet says, in English and Vietnamese |

It's plain Swift, SwiftUI and AppKit with no dependencies, built with `swiftc`.

## License

[MIT](LICENSE)
