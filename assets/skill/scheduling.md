# LifeOS Scheduling Skill

> Version: 1 (2026-11-03)
> Canonical copy: the Obsidian vault skill folder (the plugin reads it as one of its skills).
> Phone copy: `assets/skill/scheduling.md` — must stay content-identical to the canonical copy.
> Used by: the Stage 1 phone AI and the Obsidian plugin. Stage 0 does not call AI; this file is the reference ruleset.

## Purpose

This is the scheduling brain, not a task decomposer and not a completion tracker.

- Input: tasks (text, urgency/importance 1–10, ddl, estimated minutes, weekly-fixed pattern, pinned, color), already-planned day slices, fixed commitments.
- Output: a day view of planned slices and, when necessary, a conflict that needs the user's decision.
- The phone plans and displays; the Obsidian workbench does the actual work and records completion. Completion events come from Obsidian only.

## Non-negotiable rules

1. **Protect sleep, meals and fixed commitments.** Fixed weekly items (classes, appointments) win. Never move them silently.
2. **Do not fill the day.** Plan at most 60–70% of the user's available awake time; keep slack for the unexpected.
3. **Apply a 1.25–1.5× buffer** to the user's estimate when allocating. The estimate is a target, not a promise.
4. **Never silently schedule past a hard ddl.** If the ddl cannot be met, surface a conflict and ask the user; do not overbook.
5. **Long tasks become daily slices.** Split the remaining estimate across days; all slices of one task share the task color; they do not have to be at the same time of day.
6. **No invented subtasks and no task decomposition.** If a task is too big, let the user or Obsidian decompose it; the phone only allocates the remaining minutes.
7. **Priority order:** fixed commitments → hard ddl → importance → urgency → backlog. U&I are the user's raw 1–10 scores; the Obsidian plugin uses the same values for its U/I scatter. Do not rewrite the user's scores.
8. **Weekly-fixed tasks:** generate the occurrences inside the chosen weekdays/date range; the same task stays one template. Changing the template does not silently rewrite already generated slices (Stage 0); the user can delete/recreate or adjust a single day.
9. **Reschedule on interruption:** move the remaining future slices; never rewrite the past; keep the same color.
10. **The phone never records completion.** Do not infer done from time passing. Completion is an Obsidian check-off event.
11. **Keep the phone lightweight:** the phone is a plan/capture surface; the workbench is Obsidian. Do not optimize for phone engagement, streaks or notifications.
12. **One task, one color.** Every day slice of a task uses the task's persistent color; the task list and day view must not invent per-day colors.

## Conflict behaviour

When the remaining estimate cannot fit before the ddl:

1. Report the shortfall in minutes.
2. Offer 2–3 options (drop, extend, reduce scope, move a fixed item).
3. Wait for the user; never silently overbook.

## Stage 0 vs Stage 1

- **Stage 0 (now):** manual planning; this skill is the human-facing ruleset and the target for the phone UI (day slices, weekly fixed, no completion).
- **Stage 1 (after the Stage 0 gate):** AI suggestion vs manual. The skill is the AI's rule set. The experiment measures planning time, ddl misses, capture completeness and stress; completion is secondary.

## Consistency

The canonical copy lives in the Obsidian vault; the phone copy is bundled at `assets/skill/scheduling.md`. Keep the contents identical; bump the version when a rule changes and update both sides together. The Obsidian plugin may expose this file as one of its skills.
