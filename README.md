# LifeOS

手机优先的「待办 + 轻笔记混合」记录 app。Flutter + Drift (SQLite)，一套代码 Android / Windows。

## 项目文档
管理文档在仓库根目录（与代码同仓维护）：
- `CLAUDE.md` — 编码工作约定（唯一真相源）
- `PROJECT_STATE.md` — 项目总档案 / 交接入口
- `FEATURES.md` — 功能范围与路线图
- `QA_FINDINGS.md` — 验收报告与缺陷清单
- `TECH_STACK.md` — 技术选型依据
- `WORKLOG.md` — 施工日志

## 开发
```bash
flutter pub get
flutter run -d windows   # 桌面预览（需开发者模式以支持 symlink）
flutter build apk --release
```

## 测试
```bash
flutter test        # 单元测试（rrule / migration / repository）
flutter analyze
```
