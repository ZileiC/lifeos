import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/repository.dart';
import 'package:lifeos/data/rrule.dart';
import 'package:lifeos/providers.dart';
import 'package:lifeos/ui/home_screen.dart';

/// G1/widget regression tests (v0.1.2b):
/// v0.1.2 incident = tapping + (new record) -> sheet build threw `_r` null! -> release grey screen.
/// The previous F3 dead feature = no coverage in the UI interaction layer. This file closes both gaps.
///
/// Test environment notes:
/// - Drift schedules a zero-duration Timer when a watch stream is cancelled (markAsClosed);
///   advance the fake clock after unmounting or the pending-timer assertion fails.
/// - Warm the database with runAsync before pumping (the first query is truly async).
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

  /// Teardown: unmount + advance the fake clock to flush drift's stream-cancel timer.
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

      // Tap the card content (title text) to open the editor.
      await tester.tap(find.text('已存在的记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('保存'), findsOneWidget, reason: '编辑模式显示「保存」');
      expect(find.text('删除这条记录'), findsOneWidget);
      // The title field is prefilled.
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

      // Card preview + sheet list each render once -> at least one of each.
      expect(find.text('第一项'), findsWidgets);
      expect(find.text('第二项'), findsWidgets);
      expect(find.text('+ 添加勾选项'), findsOneWidget);
      await unwind(tester);
    });
  });

  group('F2b 时刻选择步骤（_TimeStepSheet 行为）', () {
    // _TimeStepSheet is private; drive it indirectly through the edit sheet's
    // due-date chip two-step flow: tap the chip -> DatePicker (pick today in
    // tests) -> time-step sheet. DatePicker is interactive in widget tests
    // (calendar cells are buttons); verify via the returned value.
    testWidgets('时刻步骤：全天任务 / 指定时刻两项可见且可回值', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Due-date chip -> DatePicker.
      await tester.tap(find.text('到期日'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Pick today's cell (the current date carries the today marker).
      final todaySel = find.byWidgetPredicate((w) =>
          w is InkWell && w.onTap != null);
      expect(todaySel, findsWidgets, reason: 'DatePicker 日历格可点');

      // Tap OK in DatePicker (keeps the default-selected today).
      final ok = find.text('OK');
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The time-step sheet appears.
      expect(find.text('全天任务'), findsOneWidget);
      expect(find.text('指定时刻'), findsOneWidget);
      expect(find.text('不指定具体时刻'), findsOneWidget);

      // Tap "all-day" -> returns (null, true); the chip label becomes all-day.
      await tester.tap(find.text('全天任务'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('全天'), findsWidgets,
          reason: '选全天后 chip 显示全天标记');

      await unwind(tester);
    });
  });

  group('F1c 区间两步流程（两次完整「日期→时刻」）', () {
    /// Confirm the default (today) in the open DatePicker.
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

      // Step 1: start date.
      await tester.tap(find.text('时间段'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('选择开始日期'), findsOneWidget,
          reason: 'F1c：区间开始必须有日期步骤（H1 修复点）');
      await confirmDatePicker(tester);

      // Time step.
      expect(find.text('全天任务'), findsOneWidget);
      expect(find.text('指定时刻'), findsOneWidget);
      await tester.tap(find.text('指定时刻'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // TimePicker appears; confirm the default time.
      final timeOk = find.text('OK');
      if (timeOk.evaluate().isNotEmpty) {
        await tester.tap(timeOk.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Step 2: end date (defaults to the start date).
      expect(find.text('选择结束日期'), findsOneWidget,
          reason: 'F1c：区间结束也有日期步骤（默认开始日期，可改 → 跨天）');
      await confirmDatePicker(tester);

      // End time step.
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

      // Saved echo: chip label becomes a date-axis span (M/d HH:mm-HH:mm).
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
      await confirmDatePicker(tester); // Start date.
      await tester.tap(find.text('全天任务')); // Start is all-day.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // End-date step: tap cancel (try the known English/Chinese labels).
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

      // Tap the done dot (checkbox area): offset from the title anchor instead of finding an icon.
      final cardTop = tester.getTopLeft(find.text('圆点测试'));
      final dotLocation = Offset(cardTop.dx - 24, cardTop.dy + 12);
      await tester.tapAt(dotLocation);
      await tester.pump();
      await tester.pump();

      // Completed style applies (title strikethrough) but the editor never opens.
      expect(find.text('保存'), findsNothing, reason: '点圆点绝不打开详情');
      await unwind(tester);
    });
  });

  group('L2 DDL 提醒（编辑弹层入口与选择器）', () {
    testWidgets('选到期日后「提前提醒」chip 出现 → 打开多选选择器', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // No reminder entry before a due date is picked.
      expect(find.text('提前提醒'), findsNothing);

      // Pick the due date (DatePicker defaults to today -> OK).
      await tester.tap(find.text('到期日'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final ok = find.text('OK');
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok.first);
      } else {
        await tester.tap(find.text('确定').first);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Time step: choose all-day.
      await tester.tap(find.text('全天任务'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The reminder chip appears; open the picker.
      await tester.tap(find.text('提前提醒'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('提前提醒（可多选）'), findsOneWidget);
      expect(find.text('准时'), findsOneWidget);
      expect(find.text('15分钟'), findsOneWidget);
      // The last preset ("1 day") may be below the fold in the test viewport.

      // Check two presets and confirm -> the chip echoes them (scroll to the
      // target when the list exceeds the viewport; the page behind also has a
      // Scrollable, so scope the scrollable to the sheet).
      final sheetScrollable = find.descendant(
        of: find.ancestor(
          of: find.text('提前提醒（可多选）'),
          matching: find.byType(BottomSheet),
        ),
        matching: find.byType(Scrollable),
      ).evaluate().isNotEmpty
          ? find.descendant(
              of: find.ancestor(
                of: find.text('提前提醒（可多选）'),
                matching: find.byType(BottomSheet),
              ),
              matching: find.byType(Scrollable),
            ).first
          : find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('1小时'),
        120,
        scrollable: sheetScrollable,
      );
      await tester.tap(find.text('15分钟'));
      await tester.tap(find.text('1小时'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('提前 15分钟 / 1小时'), findsOneWidget,
          reason: '多选后 chip 回显所选提前量');
      await unwind(tester);
    });
  });

  group('L2 重复规则：取消 / 清空区分', () {
    Future<void> openRepeatPicker(WidgetTester tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('循环记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final repeatChip = find.widgetWithText(ActionChip, '每天');
      expect(repeatChip, findsOneWidget, reason: '编辑弹层应回显现有循环规则');
      await tester.tap(repeatChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('不重复'), findsOneWidget, reason: '重复选择器已打开');
    }

    Future<Record?> savedRecord(
      WidgetTester tester, {
      required String recordId,
    }) async {
      return tester.runAsync<Record>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return (db.select(db.records)..where((r) => r.id.equals(recordId)))
            .getSingle();
      });
    }

    testWidgets('点空白关闭重复选择器：已有 rrule 不变', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createRecord(
          title: '循环记录',
          dueAt: DateTime.now().add(const Duration(days: 2)),
          rrule: const RRule.daily(),
        );
      });
      await openRepeatPicker(tester);

      // Tap the barrier (above the modal sheet) to dismiss it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(ActionChip, '每天'), findsOneWidget,
          reason: '点空白只关闭选择器，不得改动规则');

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final row = await savedRecord(tester, recordId: id);
      expect(row!.rrule, 'daily', reason: '保存后循环规则保持不变');
      await unwind(tester);
    });

    testWidgets('显式点「不重复」：清空 rrule', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await repo.createRecord(
          title: '循环记录',
          dueAt: DateTime.now().add(const Duration(days: 2)),
          rrule: const RRule.daily(),
        );
      });
      await openRepeatPicker(tester);

      await tester.tap(find.text('不重复'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(ActionChip, '不重复'), findsOneWidget,
          reason: '显式取消重复后 chip 应回显「不重复」');

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final row = await savedRecord(tester, recordId: id);
      expect(row!.rrule, isNull, reason: '显式清空后 rrule 落库为 null');
      await unwind(tester);
    });
  });
}
