# UX / Usage-Logic Audit

> Written 2026-11-04 after a day of real use. Scope: the flows a person actually walks, not the code style. No fixes applied yet; this is the "what is wrong" list, ordered by how much it hurts.

## The verdict

The app asks for too much input and offers too few direct actions. Every operation that should be one gesture is a chain of sheets. The day view — the thing the product is for — is a read-only picture you can only edit through the task list.

## P0 — the flows that make it feel broken

### 1. Adding a task to a day takes 5+ steps

Current flow:

1. switch to 日视图
2. tap 排任务
3. pick a task from a modal list (no search, no recents)
4. tap the task
5. slice editor: date, start time, duration
6. save
7. sheet closes, back to the day

And if the task doesn't exist yet: task list → FAB → task editor (title, U/I 10 chips, deadline, estimate, weekly…) → save → back → 日视图 → 排任务 → pick → slice editor.

What a calendar app does: tap the empty time slot, type a title, done. The task and its slice are one action.

**Fix direction:** tapping an empty area of the day grid creates a slice at that time (snapped to 15/30 min) with an inline title input; pressing Enter creates a minimal task + slice. The full task editor stays for later.

### 2. The day grid cannot be edited directly

- Blocks can't be dragged or resized.
- Empty slots have no action.
- The only way to change a slice is tap → sheet → date/time/duration → save.
- The header 排任务 and the day-view FAB do the same thing (duplicate entry points).
- The scroll starts at "now − 2h", but there is no "jump to now" once you've scrolled away.

**Fix direction:** tap empty slot → create; drag block → move; drag bottom edge → resize; long-press → delete/duplicate; keep one add entry point.

### 3. The phone still has no completion

The C′ decision says completion lives in Obsidian. In daily use this is the biggest psychological break: the phone shows a plan you can never tick off. The user ends up opening a second app to record what was done.

This is a product decision, not a bug. But the audit has to say it: **without any completion affordance the phone cannot be a daily driver**. Options:

- a Stage 2 "done" event on the phone that only Obsidian normally owns;
- an explicit "planned only, go to Obsidian to finish" affordance that is one tap away;
- or accept that the phone is a capture surface and stop pretending it is the day screen.

### 4. The task list is the default screen

The daily object is the day, but the app opens on the task list. The day view is one segment away. Every morning costs a switch.

**Fix direction:** default to the day; the task list is the backlog/inbox tab.

## P1 — friction that adds up

### 5. "剩余 0 / 预估 90 分钟"

The label is arithmetic, not meaning. "剩余 0" reads as "nothing left to do" (i.e. done), when it actually means "fully planned". Over-planned tasks show "剩余 0" too.

**Fix direction:** say planned vs estimate ("已排 90 / 预估 90") and flag over-allocation; never use "剩余" for a task with no completion state.

### 6. Task capture is heavy

A quick thought costs: title, 10 U chips, 10 I chips, deadline (date + time picker), estimate, optional weekly pattern, note only in the detail sheet. That is a form, not capture.

**Fix direction:** title-first quick add; U/I and estimate optional and settable later; note inline in the same editor.

### 7. The task picker is a wall

A modal list of every active task, no search, no recent, no grouping. With 30+ tasks it is unusable.

**Fix direction:** search + recents + "new task" entry inside the picker; or bypass the picker entirely (see P0-1).

### 8. Weekly-fixed tasks are hard to verify

After creating a weekly task you have to navigate to a matching day to see whether the slices are right; the task row only says "每周一/三/五 · 每次 90 分钟". Editing the template does not regenerate slices (documented), but the UI does not say so at edit time.

**Fix direction:** show the generated slice count and next occurrence in the detail; warn on template edit that existing slices stay.

### 9. Batch operations are hidden

Long-press enters selection; delete/move live in a bottom bar; undo is a snackbar. Nothing indicates long-press is available.

**Fix direction:** an explicit "select" affordance in the header, and undo surfaced as a persistent "撤销" action for the last destructive op.

### 10. AI: setup and latency are invisible

- First run: the AI button does nothing useful until a key is entered; the only hint is a snackbar after the tap.
- No onboarding, no "test connection" guidance, no cost estimate.
- Suggestions arrive as a sheet with no progress beyond a spinner; there is no cancel on the request itself.
- No streaming; a 10s wait feels broken.

**Fix direction:** first-run card in the day view ("connect DeepSeek / add provider"); cancellable request; show elapsed time; stream or at least show "AI 正在排…" with a cancel.

### 11. Q&A has no memory beyond the sheet

Five turns exist only while the sheet is open. Closing it loses the conversation, which makes follow-ups awkward.

**Fix direction:** persist the last N turns per day (local only), or make it explicit that the sheet is ephemeral.

### 12. Copy and hierarchy

- "AI 排" vs "排任务" vs "问 AI" vs "AI 设置" — four AI-adjacent entries with no clear hierarchy.
- The task row's metadata line (`无截止 · 剩余 0 / 预估 90 分钟`) is a wall of numbers.
- No empty-state guidance on the day view (a blank grid with a red line explains nothing).

## Bugs / suspected bugs

1. **Windows: day view showed no slices after the sample data was seeded**, while the task list showed the tasks and the DB contained 8 slices. The phone screenshot renders them. Likely a query/timezone/`DateTime` conversion difference on the Windows build; not yet root-caused.
2. **`TaskMath.remainingMinutes` semantics** leak into the row label and will keep confusing users (see P1-5).
3. **CI was red for three runs**: tests hard-coded `+08:00`; fixed in `9263634` by using local ISO strings. The CI run after the fix is the first honest green.
4. **AI Q&A / schedule plan validation** relies on `DateTime.toLocal()` and the target-day comparison; a UTC CI exposed it. The production code is fine for a single timezone, but timezone changes (travel) are untested.
5. **The `AiAskSheet` `_history`** keeps messages in memory only and slices `_messages`; the last-10 trim is untested.
6. **The day grid has no "jump to now"** after scrolling, and the current-time line is only drawn when `isToday`.
7. **`fetchSlicesForDay`/`watchSlicesForDay`** both exist; the AI uses the fetch variant, the UI the watch variant. Duplication is a future divergence risk.
8. **The Windows DB was seeded with sample data**; this is a local dev artifact, not app behavior, but it means the Windows preview no longer reflects an empty install.

## What I would fix first (proposed order)

1. **Empty-slot tap creates task+slice** (kills the 5-step flow, makes the grid editable).
2. **Default to the day view**.
3. **Drag/resize/delete on blocks + one add entry point**.
4. **Fix the row label** ("已排 / 预估", over-allocation marker).
5. **Quick capture**: title-first, everything else optional.
6. **Completion affordance** — needs a product decision, not a patch.
7. **AI onboarding + cancellable request + first-run hint**.
8. **Windows day-view slice rendering bug** root cause.
9. **Task picker search/recents**, weekly generation feedback, batch discoverability.

Step 6 is the one that decides whether the phone can be the daily driver. Steps 1–5, 7–9 are straightforward UI work. Step 8 is a real bug and should be reproduced before any more feature work.

## Note on scope

This audit is deliberately about the phone app's usage logic. The Obsidian-side contract is out of scope; the HTML template and the AI services are functionally fine but are not the reason the app feels hard to use.
