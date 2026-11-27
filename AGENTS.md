# Review conventions — session-lights

Personal Windows 10 widget (PowerShell 5.1 + WPF), local-only. Reviewers: these are deliberate, do not flag them.

- An unnamed session falls back to the cwd folder name. Desktop sessions always carry a sidebar name, so the fallback is cosmetic.
- The SessionStart hook is wired in the user's own `~/.claude/settings.json`; the scripts and their `settings.json` stay in this folder.
- `-Stop` / `-Restart` reset race and the `-Probe` / `-SessionsDir` side paths are debug entry points; the race window is milliseconds.
- pid reuse / unreadable StartTime fallback: Claude Code always writes `procStart`, and claude.exe is not elevated.
