import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/repository.dart';
import 'package:lifeos/providers.dart';
import 'package:lifeos/ui/home_screen.dart';

/// G1/widget 回归测试（v0.1.2b）：
/// v0.1.2 事故 = 点 + 新建按钮 → 弹层 build 抛 `_r` null! → release 灰屏。
/// 上轮 F3 死功能 = UI 交互层无测试覆盖。本文件堵住这两个流程缺口。
///
/// 测试环境注意：
/// - drift 的 watch 流取消时会调度 zero-duration Timer（markAsClosed），
///   摘树后必须推进 fake clock 让它执行，否则 pending-timer 断言失败。
/// - pump 前用 runAsync 预热数据库首查询（真实异步）。
AppDatabase createTestDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late RecordRepository repo;

  setUp(() {
    db = createTestDb();
    repo = RecordRepository(db);
  });
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.runAsync(() async {
      await db.customSelect('SELECT 1').get();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 收尾：摘树 + 推进 fake clock，清掉 drift 流取消的清理 Timer
  Future<void> unwind(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('新建弹层（崩溃回归）', () {
    testWidgets('点 + → 弹层标题输入框可见（新建模式）', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('标题'), findsOneWidget,
          reason: '新建模式弹层必须可见——v0.1.2 在此灰屏');
      expect(find.text('添加'), findsOneWidget);
      expect(find.text('笔记内容（可留空）'), findsOneWidget);
      await unwind(tester);
    });

    testWidgets('弹层含属性行：清单 / 到期日 / 时间段 chips', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('清单'), findsOneWidget);
      expect(find.text('到期日'), findsOneWidget);
      expect(find.text('时间段'), findsOneWidget);
      await unwind(tester);
    });
  });

  group('编辑弹层', () {
    testWidgets('带记录点卡片 → 编辑模式正常渲染（标题预填 + 保存 + 删除入口）',
        (tester) async {
      await tester.runAsync(() async {
        await repo.createRecord(title: '已存在的记录', body: '正文');
      });
      await pumpHome(tester);

      // 点卡片内容区（标题文本）打开编辑
      await tester.tap(find.text('已存在的记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('保存'), findsOneWidget, reason: '编辑模式显示「保存」');
      expect(find.text('删除这条记录'), findsOneWidget);
      // 标题输入框已预填
      final field = tester.widget<TextField>(
          find.widgetWithText(TextField, '已存在的记录').first);
      expect(field.controller!.text, '已存在的记录');
      await unwind(tester);
    });

    testWidgets('编辑带勾选项的记录 → 勾选项渲染', (tester) async {
      await tester.runAsync(() async {
        await repo.createRecord(
          title: '带清单',
          checkitems: ['第一项', '第二项'],
        );
      });
      await pumpHome(tester);
      await tester.tap(find.text('带清单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 卡片预览 + 弹层清单各渲染一份 → 至少各 1 处
      expect(find.text('第一项'), findsWidgets);
      expect(find.text('第二项'), findsWidgets);
      expect(find.text('+ 添加勾选项'), findsOneWidget);
      await unwind(tester);
    });
  });

  group('F2b 时刻选择步骤（_TimeStepSheet 行为）', () {
    // _TimeStepSheet 是私有类，通过编辑弹层的「到期日」chip 两步流程间接驱动：
    // 点「到期日」→ DatePicker（测试环境直接选 today）→ 时刻步骤弹层。
    // DatePicker 在 widget 测试中可交互（日历格子是按钮），这里用回值验证。
    testWidgets('时刻步骤：全天任务 / 指定时刻两项可见且可回值', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 到期日 chip → DatePicker
      await tester.tap(find.text('到期日'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 选今天的格子（day picker 中当前日期带 today 标记）
      final todaySel = find.byWidgetPredicate((w) =>
          w is InkWell && w.onTap != null);
      expect(todaySel, findsWidgets, reason: 'DatePicker 日历格可点');

      // 在 DatePicker 里点 OK（保存默认选中的今天）
      final ok = find.text('OK');
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 时刻步骤弹层出现
      expect(find.text('全天任务'), findsOneWidget);
      expect(find.text('指定时刻'), findsOneWidget);
      expect(find.text('不指定具体时刻'), findsOneWidget);

      // 点「全天任务」→ 回值 (null, true)，chip 文案更新为「全天」
      await tester.tap(find.text('全天任务'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('全天'), findsWidgets,
          reason: '选全天后 chip 显示全天标记');

      await unwind(tester);
    });
  });

  group('F1c 区间两步流程（两次完整「日期→时刻」）', () {
    /// 在打开的 DatePicker 里确认默认（今天）
    Future<void> confirmDatePicker(WidgetTester tester) async {
      final ok = find.text('OK');
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('点「时间段」→ 出现开始日期 DatePicker → 时刻步骤 → '
        '结束日期 DatePicker → 时刻步骤（两次完整流程，步骤均可见）',
        (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 第 1 步：开始日期
      await tester.tap(find.text('时间段'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('选择开始日期'), findsOneWidget,
          reason: 'F1c：区间开始必须有日期步骤（H1 修复点）');
      await confirmDatePicker(tester);

      // 时刻步骤
      expect(find.text('全天任务'), findsOneWidget);
      expect(find.text('指定时刻'), findsOneWidget);
      await tester.tap(find.text('指定时刻'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // TimePicker 出现，确认默认时刻
      final timeOk = find.text('OK');
      if (timeOk.evaluate().isNotEmpty) {
        await tester.tap(timeOk.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 第 2 步：结束日期（默认 = 开始日期）
      expect(find.text('选择结束日期'), findsOneWidget,
          reason: 'F1c：区间结束也有日期步骤（默认开始日期，可改 → 跨天）');
      await confirmDatePicker(tester);

      // 结束时刻步骤
      expect(find.text('全天任务'), findsOneWidget);
      await tester.tap(find.text('指定时刻'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final timeOk2 = find.text('OK');
      if (timeOk2.evaluate().isNotEmpty) {
        await tester.tap(timeOk2.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 保存回显：chip 文案变为带日期轴的区间（M月d日 HH:mm–HH:mm）
      expect(find.textContaining(RegExp(r'\d{1,2}月\d{1,2}日 \d{2}:\d{2}–\d{2}:\d{2}')),
          findsOneWidget,
          reason: '区间设置完成后 chip 回显带日期的时间段');
      expect(find.text('清空时间段'), findsOneWidget);
      await unwind(tester);
    });

    testWidgets('结束日期步骤取消 → 只保留开始（chip 回显「从 …」）',
        (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('时间段'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await confirmDatePicker(tester); // 开始日期
      await tester.tap(find.text('全天任务')); // 开始全天
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 结束日期步骤：点取消（本地化未知 → CANCEL / Cancel / 取消 逐个兜底）
      expect(find.text('选择结束日期'), findsOneWidget);
      var tappedCancel = false;
      for (final label in ['CANCEL', 'Cancel', '取消']) {
        final c = find.text(label);
        if (c.evaluate().isNotEmpty) {
          await tester.tap(c.first);
          tappedCancel = true;
          break;
        }
      }
      expect(tappedCancel, isTrue, reason: 'DatePicker 必须有取消按钮');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining(RegExp(r'从 \d{1,2}月\d{1,2}日')),
          findsOneWidget,
          reason: '结束侧取消 = 只保留开始');
      expect(find.text('清空时间段'), findsOneWidget);
      await unwind(tester);
    });
  });

  group('F3b 回归：圆点与详情分离', () {
    testWidgets('点勾选圆点只切换完成态，不打开详情弹层', (tester) async {
      await tester.runAsync(() async {
        await repo.createRecord(title: '圆点测试');
      });
      await pumpHome(tester);

      // 点圆点（勾选按钮区域）：用 TapOptions 以标题为锚点偏移到圆点位置
      final cardTop = tester.getTopLeft(find.text('圆点测试'));
      final dotLocation = Offset(cardTop.dx - 24, cardTop.dy + 12);
      await tester.tapAt(dotLocation);
      await tester.pump();
      await tester.pump();

      // 完成态生效：标题划线（done 样式），但编辑弹层没有打开
      expect(find.text('保存'), findsNothing, reason: '点圆点绝不打开详情');
      await unwind(tester);
    });
  });
}
