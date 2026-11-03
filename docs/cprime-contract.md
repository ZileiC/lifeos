# C′ 跨端数据 / 事件契约（Stage 0）

> 状态：Stage 0 文档契约；**不包含 OB 插件实现或运行时同步**。
> 目的：让手机端与未来的 Obsidian 插件对“任务 / 日片 / 完成事件 / 额外项”使用同一套字段语义。
> 方向：手机写核心日程；OB 写完成事件与额外任务/时间块，异步回传；手机不改 OB 的核心块。

## 1. 责任边界

| 数据 | 写者 | 读法 |
|---|---|---|
| 任务（Task） | 手机 | OB 只读 |
| 日片（DaySlice） | 手机（手动/每周固定生成） | OB 只读 |
| 完成事件（CompletionEvent） | OB（划掉日片） | 手机异步拉取，只读 |
| 额外任务/手动块（ExtraItem） | OB（电脑前临时添加） | 手机异步拉取，作为固定项避让 |
| 排程 skill | OB 本地 canonical + 手机副本 | 两边内容一致 |

- 手机**不写**完成状态；OB **不写**手机的核心日程/日片。
- 额外项由 OB 写入，手机将其视为固定；手机 AI 不得覆盖/移动额外项。
- 所有数据遵循：UUID 主键、`createdAt`/`updatedAt`、墓碑 `deletedAt`；禁物理删除（清理例外须双端确认）。

## 2. Task

```json
{
  "id": "0f5b3c1e-...",
  "title": "写报告",
  "note": "第三章",
  "urgency": 7,
  "importance": 9,
  "dueAt": "2026-11-10T18:00:00+08:00",
  "dueHasTime": true,
  "estimatedMinutes": 120,
  "color": 4286505913,
  "pinned": false,
  "recurrence": null,
  "createdAt": "2026-11-03T10:00:00+08:00",
  "updatedAt": "2026-11-03T10:00:00+08:00",
  "deletedAt": null
}
```

- `urgency` / `importance`：**1–10 整数原值**；OB 未来用它们画精确的 U/I 四象限点阵，不得重排/归一化。
- `dueAt`：ISO 8601 带时区；`dueHasTime=false` 表示只有日期（按当天截止），没有单独“全天”UI 概念。
- `estimatedMinutes`：普通任务为总预估；每周固定任务为**每次时长**。
- `color`：ARGB；同一任务所有日片共用；null 时客户端按 id 稳定派生。
- `recurrence`：null 或：

```json
{
  "weekdays": [1, 3, 5],
  "startMinutes": 540,
  "durationMinutes": 60,
  "fromDate": "2026-09-01",
  "toDate": "2026-12-31"
}
```

- `weekdays` 1=周一…7=周日；`startMinutes` 当天分钟；日期含首尾；单任务上限 366 天/500 片。

## 3. DaySlice

```json
{
  "id": "7c1a...",
  "taskId": "0f5b3c1e-...",
  "startAt": "2026-11-03T09:00:00+08:00",
  "endAt": "2026-11-03T10:00:00+08:00",
  "createdAt": "2026-11-03T08:50:00+08:00",
  "updatedAt": "2026-11-03T08:50:00+08:00",
  "deletedAt": null
}
```

- 日片是计划，不是完成记录；手机不写完成。
- 跨天片 Stage 0 不支持；`endAt > startAt`。

## 4. CompletionEvent（OB → 手机）

```json
{
  "id": "c0f1...",
  "taskId": "0f5b3c1e-...",
  "sliceId": "7c1a...",
  "completedAt": "2026-11-03T10:05:00+08:00",
  "source": "obsidian",
  "deletedAt": null
}
```

- 只有 OB 产生；手机只读；用于剩余时间/重排（Stage 1）。
- `sliceId` 可空（整任务完成）；撤销完成用墓碑事件，不物理删除。

## 5. ExtraItem（OB → 手机）

```json
{
  "id": "e2a...",
  "kind": "task",
  "title": "临时加会",
  "startAt": "2026-11-03T15:00:00+08:00",
  "endAt": "2026-11-03T16:00:00+08:00",
  "note": "",
  "source": "obsidian",
  "createdAt": "2026-11-03T14:10:00+08:00",
  "updatedAt": "2026-11-03T14:10:00+08:00",
  "deletedAt": null
}
```

- `kind`: `task`（额外任务）或 `block`（临时时间块）。
- 手机把额外项视为**固定**，AI 排程必须避让；手机不覆盖/不移动。
- 额外项只在 OB 产生；手机端只读展示（Stage 1 起）。

## 6. Skill 文件

- canonical：Obsidian vault 内的 skill 文件。
- 手机副本：`assets/skill/scheduling.md`。
- 要求：内容一致；版本号同步；手机端不自行改写规则。

## 7. Stage 0 范围

- 手机端已实现：Task / DaySlice / RecurrenceSpec（本地）。
- **未实现**：CompletionEvent / ExtraItem 的运行时同步；本文件只是字段契约。
- OB 插件、系统日历、小组件、通知不在 Stage 0 范围。

## 8. 冲突与隐私

- 双端字段冲突以“手机核心日程优先、OB 额外项固定避让”处理；冲突事件需用户决策，不静默覆盖。
- 数据仅本地/用户自有存储；不引入云同步或第三方账户。
