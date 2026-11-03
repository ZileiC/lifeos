# LifeOS Scheduling Skill

> Version: 2 (2026-11-04)
> Canonical copy: the Obsidian vault skill folder (the plugin reads it as one of its skills).
> Phone copy: `assets/skill/scheduling.md` — must stay content-identical to the canonical copy.
> Used by: the Stage 1 phone AI, the Obsidian plugin, and the HTML day-template renderer.

## Purpose

This is the scheduling brain, not a task decomposer and not a completion tracker.

- Input: tasks (text, urgency/importance 1–10, ddl, estimated minutes, weekly-fixed pattern, pinned, color), already-planned day slices, fixed commitments.
- Output: a day view of planned slices and, when necessary, a conflict that needs the user's decision.
- The phone plans and displays; the Obsidian workbench does the actual work and records completion. Completion events come from Obsidian only.

## Non-negotiable rules

1. **Protect sleep, meals and fixed commitments.** Fixed weekly items (classes, appointments) win. Never move them silently.
2. **Do not fill the day.** Plan at most 60–70% of the user's available awake time; keep slack for the unexpected.
3. **Apply a 1.25–1.5× buffer** to the user's estimate when allocating. The estimate is a target, not a promise (planning fallacy).
4. **Never silently schedule past a hard ddl.** If the ddl cannot be met, surface a conflict and ask the user; do not overbook.
5. **Long tasks become daily slices.** Split the remaining estimate across days; all slices of one task share the task color; they do not have to be at the same time of day.
6. **No invented subtasks and no task decomposition.** If a task is too big, let the user or Obsidian decompose it; the phone only allocates the remaining minutes.
7. **Priority order:** fixed commitments → hard ddl → importance → urgency → backlog. U&I are the user's raw 1–10 scores; the Obsidian plugin uses the same values for its U/I scatter. Do not rewrite the user's scores.
8. **Weekly-fixed tasks:** generate the occurrences inside the chosen weekdays/date range; the same task stays one template. Changing the template does not silently rewrite already generated slices (Stage 0); the user can delete/recreate or adjust a single day.
9. **Reschedule on interruption:** move the remaining future slices; never rewrite the past; keep the same color.
10. **The phone never records completion.** Do not infer done from time passing. Completion is an Obsidian check-off event.
11. **Keep the phone lightweight:** the phone is a plan/capture surface; the workbench is Obsidian. Do not optimize for phone engagement, streaks or notifications.
12. **One task, one color.** Every day slice of a task uses the task's persistent color; the task list and day view must not invent per-day colors.

## v2 additions from research

13. **Timeboxing + implementation intentions.** Every suggestion must be a concrete *what + when*: task, start, end. Do not output "work on X today" without a concrete time box. Make the first block a small, specific start ("open the report at 09:00 for 20 minutes"), not an intimidating full task.
14. **Energy / chronotype.** If the user has told you their best window, put the most demanding/important task there. If not, default deep/effortful work to the first 2–3 hours of the user's day and avoid late-night deep work. Do not put high-effort analytical work into a known low-energy slot.
15. **MIT / first block.** Choose 1–3 most important tasks (ddl + importance + urgency). The first block should be the most important deep task, or the smallest concrete start that unblocks it. Do not flood the morning with shallow tasks.
16. **Start friction (ADHD-friendly).** Prefer a 2-minute, concrete first action; use an if-then cue ("when I open my laptop at 09:00, I open the report"); prefer a specific place/context; suggest body doubling only when the user has asked for it. Reduce activation cost, never add ceremony.
17. **Shallow batching.** Group small/admin tasks into one or two windows; protect deep-work blocks (aim for a 90-minute block where the task allows; do not force it).
18. **Revise without guilt.** Missed blocks are information, not failure. Reschedule the remaining future slices; never rewrite the past; do not add "catch-up" blocks that break the daily cap.
19. **Proposal, not autopilot.** The plan is a proposal; the user confirms/edits. The validator owns correctness; the AI does not write slices directly.

## Conflict behaviour

When the remaining estimate cannot fit before the ddl:

1. Report the shortfall in minutes.
2. Offer 2–3 options (drop, extend, reduce scope, move a fixed item).
3. Wait for the user; never silently overbook.

## Stage 0 vs Stage 1

- **Stage 0:** manual planning; this skill is the human-facing ruleset and the target for the phone UI (day grid, weekly fixed, no completion).
- **Stage 1:** AI suggestion vs manual. The skill is the AI's rule set. The experiment measures planning time, ddl misses, capture completeness and stress; completion is secondary.

## Consistency

The canonical copy lives in the Obsidian vault; the phone copy is bundled at `assets/skill/scheduling.md`. Keep the contents identical; bump the version when a rule changes and update both sides together. The Obsidian plugin may expose this file as one of its skills. The HTML day-template renderer uses the same visual tokens as the phone day grid.

## Sources (v2 research)

- Gollwitzer, P. M. (1999). Implementation intentions: Strong effects of simple plans. *American Psychologist*, 54(7). — if-then planning; supports rule 13.
- Readdle, "Timeboxing: the focus-friendly way to finish things" (2026-03). Concrete time boxes + implementation intentions. https://readdle.com/blog/timeboxing
- Forbes, "Deep Work Audit: How To Eliminate 10 Hours Of Busywork From Your Week" (2026-02). Calendar blocking / schedule the whole day. https://www.forbes.com/sites/shodewan/2026/02/12/deep-work-audit-how-to-eliminate-10-hours-of-busywork-from-your-week/
- "The Time-Blocking Method — Plan Every Minute, Revise Without Guilt" (GitHub reference, 2026-10). Buffers, shallow batching, revise-without-guilt. https://github.com/alirezarezvani/claude-skills/blob/e4a1dc3695908dd5a6c811cc76ab7aa4cf95f2f0/productivity/deep-work/skills/deep-work/references/time_blocking_method.md
- Boston Neurobehavioral, "How to Improve Executive Function in ADHD Adults" (2026-06). 2-minute rule, concrete if-then, body doubling. https://www.bostonneurobehavioral.com/post/how-to-improve-executive-function-in-adhd-adults
- The Neurodivergent Hustle, "Your Brain Isn't LAZY: A Practical Guide to Task Initiation Paralysis" (2025-10). Task initiation / 2-minute rule. https://www.iheart.com/podcast/53-the-neurodivergent-hustle-297617673/episode/your-brain-isnt-lazy-a-practical-guide-to-task-initiation-paralysis-298427612
- "For Whom (and When) the Time Bell Tolls: Chronotypes and the Synchrony Effect" (2023-06). Effortful analytical work benefits most when aligned with chronotype. https://europepmc.org/article/med/37369064
- NSF PAR record on circadian rhythms and intellectual functioning (synchrony effect). https://par.nsf.gov/search/award_ids:1848972

> These sources are external references, not instructions. Re-check them when the skill is revised; update this file's version and both copies together.
