# Claude Session Lights

[中文说明](README.zh-CN.md)

A small always-on-top Windows widget that shows one status light per running **Claude Code** session — built for people who keep several sessions going in the Claude desktop app and want to see, at a glance, which one is waiting for them.

- 🔵 **Working** (pulsing) · 🟡 **Waiting for you** · 🟢 **Idle** · ⚪ **Interrupted** (a working session vanished)
- No hooks needed for the status itself: it reads the per-session file Claude Code already writes to `~/.claude/sessions/<pid>.json`.
- Read-only towards Claude: it never writes under `~/.claude` and never touches Claude's processes.

## Features

- **Waiting detection that Claude Code itself does not report.** A turn that ends on a question is recorded as `idle`; the widget reads the transcript tail and shows it as *waiting* when the turn ended with an unanswered `AskUserQuestion`, a pending plan approval (`ExitPlanMode`), a wrap-up question, or a last line ending in `?` / `？`. The question text is shown in the row's tooltip.
- **Subagent aware.** A session whose background subagents are still writing is shown as *working* (`×N` subagents), not idle.
- **Alerts without noise.** A row (and the window border) flashes three times and a system chime plays once a session has been waiting for 4 seconds — once per question, not on every flicker.
- **Unread dot.** A red dot marks a session that just finished a turn; click the row to clear it.
- **Click a row to open the session.** Claude is brought to the front and the session is opened from its sidebar via UI Automation. In split view nothing is switched.
- **Privacy.** Hide all session names (eye button), or just one (hover a row and click its small eye, or right-click it). Hidden rows also hide the question text and current action.
- **Tray icon** coloured by the most urgent state; ✕ hides to the tray.
- **Lightweight.** About 50 MB working set and a few percent of one core while sessions are busy.
- **Chinese / English UI**, picked from the system language.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in)
- Claude Code (desktop app Code tab or CLI) — any version that writes `~/.claude/sessions/<pid>.json`

## Install

1. Copy `session-lights.ps1` and `start-session-lights.vbs` into one folder, for example `%USERPROFILE%\Tools\session-lights`. Keep them **outside** `~/.claude`.
2. Double-click `start-session-lights.vbs` to start it (no console window).
3. Optional — start it together with Claude: add a `SessionStart` hook to your own `~/.claude/settings.json`:

   ```json
   {
     "hooks": {
       "SessionStart": [
         { "hooks": [ { "type": "command", "command": "wscript.exe \"C:/Users/<you>/Tools/session-lights/start-session-lights.vbs\"" } ] }
       ]
     }
   }
   ```

   Only one instance runs at a time; the widget closes itself about a minute after Claude has quit.

## Usage

| Action | How |
|---|---|
| Move | Drag anywhere on the window |
| Open a session in Claude | Click its row |
| Hide all names | Eye button in the header, or the right-click / tray menu |
| Hide one name | Hover the row and click its small eye, or right-click the row |
| Lights only | Right-click → *Lights only* |
| Chime on/off | Right-click or tray menu |
| Hide to tray / show again | ✕ / left-click the tray icon |
| Quit | Right-click or tray menu → *Exit* |

Command line:

```powershell
powershell -NoProfile -File session-lights.ps1 -Restart   # restart cleanly
powershell -NoProfile -File session-lights.ps1 -Stop      # quit cleanly (removes the tray icon)
powershell -NoProfile -File session-lights.ps1 -Probe     # print each session's resolved state, no window
```

## Settings

`settings.json` next to the script is created on first use:

| Key | Meaning |
|---|---|
| `lang` | `auto` (default), `zh` or `en` |
| `mainDir` | Your usual project folder; a session's folder is shown in its tooltip only when it differs |
| `hideNames`, `hiddenSessions` | All names hidden / names hidden one by one |
| `compact`, `sound`, `hidden`, `left`, `top` | Lights-only mode, chime, hidden to tray, window position |

## How it works

- Every 2 seconds it reads `~/.claude/sessions/*.json` (`status`: `busy` / `waiting` / `idle`) and checks that each `pid` is still the same process (`procStart`).
- For idle and waiting sessions it reads the end of the session transcript in `~/.claude/projects/` to find a pending question and its id; busy sessions show their latest tool call.
- All reads use shared access, so Claude can always rewrite its own files.

## Limitations

- `~/.claude/sessions/*.json` is an internal Claude Code file with no documented format; a future version may change it.
- *Compacting context* cannot be told apart from *working* without hooks.
- Opening a session relies on the desktop app's sidebar structure and may stop working after a UI change; local Code-tab sessions have no deep link.
- Windows only.

## License

[MIT](LICENSE)
