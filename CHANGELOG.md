# Changelog

Notable changes to LifeOS. The app is pre-1.0 and the format is loose.

## 0.3.0 — 2026-11-04

Stage 1, first pass:

- AI scheduling suggestions with a preview on the day grid; confirm/edit/ignore, never automatic.
- Read-only AI Q&A over tasks, slices, weekly-fixed items, DDLs, estimates and the current time; the last 5 turns are kept in memory.
- Provider selection: DeepSeek by default (`deepseek-flash` / `deepseek-v4-pro`), plus any custom OpenAI-compatible provider. Keys are stored per provider in the platform keystore.
- The day view became a 24h time grid: hour lines, a live "now" line, time blocks with a left color bar, and overlapping blocks side by side.
- A4 single-day print template sharing the phone's visual tokens, plus a sample day JSON.
- The scheduling skill (v2) is bundled and shared with the Obsidian side.
- MIT license; CI.

## 0.2.0 — 2026-11-02

C′ Stage 0:

- Phone-first capture with U&I 1–10, deadline, estimate, weekly-fixed tasks.
- Day slices; weekly generation; batch delete/move with single-step undo.
- Completion tracking removed from the phone; dark theme only.
- Drift schema v5 with a pre-migration backup.

## 0.1.4 — 2026-10-28

- App icon, comment cleanup, and three QA fixes.
