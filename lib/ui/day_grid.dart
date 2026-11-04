import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai/ai_models.dart';
import '../data/database.dart';
import '../data/task_colors.dart';
import '../data/task_repository.dart';

/// Notion-Calendar-style single-day time grid: a persistent 24h base grid with
/// hour lines, a red "now" line when the day is today, and task slices
/// positioned as time blocks. Overlapping slices are laid out side by side in
/// columns. AI suggestions are drawn as dashed, lighter blocks on top; nothing
/// is written until the user confirms them. The grid is drawn even when the
/// day is empty.
class DayGrid extends StatefulWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.slices,
    required this.isToday,
    required this.now,
    required this.onEditSlice,
    this.suggested = const <AiSliceSuggestion>[],
    this.suggestedTasks = const <String, Record>{},
    this.onTapSuggested,
  });

  final DateTime day;
  final List<DaySliceWithTask> slices;
  final bool isToday;
  final DateTime now;
  final ValueChanged<DaySliceWithTask> onEditSlice;
  final List<AiSliceSuggestion> suggested;
  final Map<String, Record> suggestedTasks;
  final ValueChanged<AiSliceSuggestion>? onTapSuggested;

  @override
  State<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends State<DayGrid> {
  static const double hourHeight = 88;
  static const double labelWidth = 52;
  static const double topOffset = 8;
  static const double blockGap = 4;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToInitial());
  }

  @override
  void didUpdateWidget(covariant DayGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day || oldWidget.isToday != widget.isToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToInitial());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpToInitial() {
    if (!_controller.hasClients) return;
    final nowMinutes = widget.now.hour * 60 + widget.now.minute;
    final target = widget.isToday
        ? (nowMinutes / 60 * hourHeight) - 2 * hourHeight
        : 8 * hourHeight;
    final max = _controller.position.maxScrollExtent;
    _controller.jumpTo(target.clamp(0, max));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.outline.withValues(alpha: 0.45);
    final nowMinutes = widget.now.hour * 60 + widget.now.minute;
    final nowY = topOffset + nowMinutes / 60 * hourHeight;
    final current = _current();
    final next = _next();
    final placements = _layout();

    return SingleChildScrollView(
      controller: _controller,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - labelWidth - 6 - 10;
          return SizedBox(
            height: topOffset + 24 * hourHeight + 24,
            child: Stack(
              children: [
                for (var hour = 0; hour < 24; hour++) ...[
                  Positioned(
                    left: 0,
                    top: topOffset + hour * hourHeight - 7,
                    width: labelWidth - 8,
                    child: Text(
                      DateFormat('HH:mm').format(DateTime(2026, 1, 1, hour)),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Positioned(
                    left: labelWidth,
                    right: 0,
                    top: topOffset + hour * hourHeight,
                    height: 1,
                    child: Container(color: lineColor),
                  ),
                ],
                if (widget.isToday)
                  Positioned(
                    left: labelWidth,
                    right: 0,
                    top: nowY,
                    height: 2,
                    child: Container(
                      key: const Key('day-now-line'),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.error.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.isToday)
                  Positioned(
                    left: 0,
                    top: nowY - 8,
                    width: labelWidth - 8,
                    child: Text(
                      '现在',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontSize: 10,
                      ),
                    ),
                  ),
                for (final placement in placements)
                  ..._positionedBlock(
                    placement,
                    available: available,
                    isCurrent: identical(placement.entry, current),
                    isNext: identical(placement.entry, next),
                    theme: theme,
                  ),
                for (var index = 0; index < widget.suggested.length; index++)
                  ..._positionedSuggested(
                    widget.suggested[index],
                    index,
                    available: available,
                    theme: theme,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _positionedBlock(
    _Placement placement, {
    required double available,
    required bool isCurrent,
    required bool isNext,
    required ThemeData theme,
  }) {
    final entry = placement.entry;
    final start = entry.slice.startAt;
    final end = entry.slice.endAt;
    final startMinutes = start.hour * 60 + start.minute;
    final durationMinutes = end.difference(start).inMinutes;
    final top = topOffset + startMinutes / 60 * hourHeight + 1;
    final height =
        (durationMinutes / 60 * hourHeight - 2).clamp(28.0, double.infinity);
    final columns = placement.columns;
    final step = columns == 1
        ? available
        : (available - (columns - 1) * blockGap) / columns;
    final left = labelWidth + 6 + placement.column * (step + blockGap);
    final color = Color(TaskColors.resolve(entry.task.color, entry.task.id));
    return [
      Positioned(
        left: left,
        width: step,
        top: top,
        height: height,
        child: _SliceBlock(
          entry: entry,
          color: color,
          isCurrent: isCurrent,
          isNext: isNext,
          onTap: () => widget.onEditSlice(entry),
        ),
      ),
    ];
  }

  /// Returned slices sorted by start, each with its column and the number of
  /// columns in its connected overlap cluster. Non-overlapping clusters keep
  /// column count 1 (full width).
  List<_Placement> _layout() {    final sorted = [...widget.slices]
      ..sort((a, b) => a.slice.startAt.compareTo(b.slice.startAt));
    final columns = <String, int>{};
    final clusterMax = <String, int>{};
    final active = <_Active>[];
    var cluster = <_Active>[];

    void closeCluster() {
      if (cluster.isEmpty) return;
      final maxColumns = cluster
              .map((item) => item.column)
              .reduce(math.max) +
          1;
      for (final item in cluster) {
        clusterMax[item.id] = maxColumns;
      }
      cluster = [];
    }

    for (final entry in sorted) {
      active.removeWhere((item) => !item.end.isAfter(entry.slice.startAt));
      if (active.isEmpty) closeCluster();
      final used = active.map((item) => item.column).toSet();
      var column = 0;
      while (used.contains(column)) {
        column++;
      }
      final item = _Active(
        id: entry.slice.id,
        end: entry.slice.endAt,
        column: column,
      );
      active.add(item);
      cluster.add(item);
      columns[entry.slice.id] = column;
    }
    closeCluster();

    return widget.slices
        .map((entry) => _Placement(
              entry: entry,
              column: columns[entry.slice.id] ?? 0,
              columns: clusterMax[entry.slice.id] ?? 1,
            ))
        .toList();
  }

  List<Widget> _positionedSuggested(
    AiSliceSuggestion slice,
    int index, {
    required double available,
    required ThemeData theme,
  }) {
    final start = slice.startAt;
    final end = slice.endAt;
    final startMinutes = start.hour * 60 + start.minute;
    final durationMinutes = end.difference(start).inMinutes;
    final top = topOffset + startMinutes / 60 * hourHeight + 1;
    final height =
        (durationMinutes / 60 * hourHeight - 2).clamp(28.0, double.infinity);
    final task = widget.suggestedTasks[slice.taskId];
    final color = task == null
        ? theme.colorScheme.primary
        : Color(TaskColors.resolve(task.color, task.id));
    return [
      Positioned(
        left: labelWidth + 6,
        width: available,
        top: top,
        height: height,
        child: _SuggestedSliceBlock(
          key: Key('suggested-$index'),
          title: task?.title ?? slice.taskId,
          color: color,
          start: start,
          end: end,
          reason: slice.reason,
          onTap: widget.onTapSuggested == null
              ? null
              : () => widget.onTapSuggested!(slice),
        ),
      ),
    ];
  }

  DaySliceWithTask? _current() {
    if (!widget.isToday) return null;
    for (final entry in widget.slices) {
      if (!entry.slice.startAt.isAfter(widget.now) &&
          entry.slice.endAt.isAfter(widget.now)) {
        return entry;
      }
    }
    return null;
  }

  DaySliceWithTask? _next() {
    if (!widget.isToday) return null;
    for (final entry in widget.slices) {
      if (entry.slice.startAt.isAfter(widget.now)) return entry;
    }
    return null;
  }
}

class _Active {
  const _Active({required this.id, required this.end, required this.column});

  final String id;
  final DateTime end;
  final int column;
}

class _Placement {
  const _Placement({
    required this.entry,
    required this.column,
    required this.columns,
  });

  final DaySliceWithTask entry;
  final int column;
  final int columns;
}

class _SliceBlock extends StatelessWidget {
  const _SliceBlock({
    required this.entry,
    required this.color,
    required this.isCurrent,
    required this.isNext,
    required this.onTap,
  });

  final DaySliceWithTask entry;
  final Color color;
  final bool isCurrent;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = DateFormat('HH:mm').format(entry.slice.startAt);
    final end = DateFormat('HH:mm').format(entry.slice.endAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('day-block-${entry.slice.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.32)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 10,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: color),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                          ),
                        ),
                        if (isCurrent)
                          const _BlockTag(text: '当前')
                        else if (isNext)
                          const _BlockTag(text: '下一块'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$start–$end',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestedSliceBlock extends StatelessWidget {
  const _SuggestedSliceBlock({
    super.key,
    required this.title,
    required this.color,
    required this.start,
    required this.end,
    required this.reason,
    required this.onTap,
  });

  final String title;
  final Color color;
  final DateTime start;
  final DateTime end;
  final String reason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startLabel = DateFormat('HH:mm').format(start);
    final endLabel = DateFormat('HH:mm').format(end);
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(
        color: color.withValues(alpha: 0.85),
        radius: 8,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: color.withValues(alpha: 0.55)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '$startLabel–$endLabel',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'AI 建议',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _BlockTag extends StatelessWidget {
  const _BlockTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
