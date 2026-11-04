# 单日日程表打印模板

> Stage 1 · `html-day-template` · 2026-11-04
> 与手机 `DayGrid` 共用同一套视觉 token；不依赖手机运行，给 OB / 打印用。

## 文件

| 文件 | 用途 |
|---|---|
| `assets/templates/day_timetable.html` | 独立 A4 打印模板，内联 sample 数据，`file://` 打开即可渲染 |
| `assets/templates/sample_day.json` | 规范 sample 数据（与模板内联数据一致） |
| `docs/day-template.md` | 本说明 |

## 数据格式

```json
{
  "date": "2026-11-04",
  "weekday": "周三",
  "slices": [
    {
      "taskId": "report",
      "title": "写周报",
      "color": "#7FA7C9",
      "startAt": "2026-11-04T09:00:00+08:00",
      "endAt": "2026-11-04T10:30:00+08:00"
    }
  ]
}
```

- `date` 仅用于日期头与页脚；时间块由 `startAt/endAt` 决定。
- `weekday` 为中文短周几（周一…周日）。
- `taskId` 必填；**同一 taskId 必须使用同一 `color`**（与手机一致）。
- `startAt/endAt` 为带时区偏移的 ISO 8601；跨天不在模板支持范围内。
- 跨天 / 过去时间由手机端 `PlanValidator` 拦截；模板只负责渲染。

## 视觉 token（与手机 DayGrid 对齐）

| Token | 手机 DayGrid | 打印模板 |
|---|---|---|
| 任务色 | `TaskColors.palette` 10 色 | 数据里的 `color`（同一组 hex） |
| 块圆角 | 8dp | 2mm |
| 重叠错开间距 | 4dp | 1.2mm |
| 左侧高亮条 | 3dp 全色 | 1.6pt 全色 |
| 块边框 | 1dp 32% | .4pt 32% |
| 块填充 | 16% 透明度 | 12% 透明度（纸面更轻，保证正文可读） |
| 每小时高度 | 88px | 9.6mm（24h = 230.4mm，A4 单页） |
| 标签列 | 52px | 16mm |
| 字体 | 系统字体 | 同一系统字体 |

任务色板（`lib/data/task_colors.dart`）：

```text
#7FA7C9  #8FBFA8  #D9B36C  #C98A8A  #9B8FC4
#6FB7B7  #C4A484  #A8B56F  #B78FB0  #8E9EC4
```

## 用法

1. 浏览器直接打开 `assets/templates/day_timetable.html`，sample 会立即渲染。
2. 替换模板内联的 `const day = { ... }`（或把 `sample_day.json` 作为数据源），刷新即可。
3. 打印：A4 纵向；页边距由 `@page` 控制；浏览器打印设置里需开启「背景图形 / Background graphics」以保留颜色。
4. OB 插件可把同一份 JSON 渲染进这个模板；模板本身不依赖手机 App。
5. Stage 1 手机端不接打印；这是 OB / 打印侧的产物。

## 与手机日视图的差异

- 打印版没有「现在」红线（打印没有实时时间）。
- 打印底色是浅色纸面；手机是深色主题。
- 其余一致：同一套任务色、圆角、左边条、重叠并排（同一套 overlap-cluster 算法）、每小时网格。
- 打印缺省只显示 title + 时间段；理由（reason）不打印，避免拥挤。

## 验收

```bash
flutter test test/day_template_test.dart
```

预期：模板文件包含 A4/@page/print CSS/token，sample JSON 合法且与模板内联数据一致，同一 taskId 同色。

手动：浏览器打开 → 打印预览应为 A4 单页；24h 网格、小时线、日期头、时间块、同任务同色、两处重叠并排。
