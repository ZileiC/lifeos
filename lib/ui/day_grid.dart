import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/task_colors.dart';
import '../data/task_repository.dart';

/// Notion-Calendar-style single-day time grid: a persistent 24h base grid with
/// hour lines, a red "now" line when the day is today, and task slices
/// positioned as time blocks. The grid is drawn even when the day is empty.
class DayGrid extends StatefulWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.slices,
    required this.isToday,
    required this.now,
    required this.onEditSlice,
  });

  final DateTime day;
  final List<DaySliceWithTask> slices;
  final bool isToday;
  final DateTime now;
  final ValueChanged<DaySliceWithTask> onEditSlice;

  @override
  State<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends State<DayGrid> {
  static const double hourHeight = 64;
  static const double labelWidth = 52;
  static const double topOffset = 8;

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
    final overlapping = _overlappingIds();
    final current = _current();
    final next = _next();

    return SingleChildScrollView(
      controller: _controller,
      child: SizedBox(
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
                height: 1.5,
                child: Container(
                  key: const Key('day-now-line'),
                  color: theme.colorScheme.error,
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
            for (final entry in widget.slices)
              _positionedBlock(
                entry,
                isCurrent: identical(entry, current),
                isNext: identical(entry, next),
                overlaps: overlapping.contains(entry.slice.id),
                theme: theme,
              ),
          ],
        ),
      ),
    );
  }

  Widget _positionedBlock(
    DaySliceWithTask entry, {
    required bool isCurrent,
    required bool isNext,
    required bool overlaps,
    required ThemeData theme,
  }) {
    final start = entry.slice.startAt;
    final end = entry.slice.endAt;
    final startMinutes = start.hour * 60 + start.minute;
    final durationMinutes = end.difference(start).inMinutes;
    final top = topOffset + startMinutes / 60 * hourHeight + 1;
    final height =
        (durationMinutes / 60 * hourHeight - 2).clamp(24.0, double.infinity);
    final color = Color(TaskColors.resolve(entry.task.color, entry.task.id));
    return Positioned(
      left: labelWidth + 6,
      right: 10,
      top: top,
      height: height,
      child: _SliceBlock(
        entry: entry,
        color: color,
        isCurrent: isCurrent,
        isNext: isNext,
        overlaps: overlaps,
        onTap: () => widget.onEditSlice(entry),
      ),
    );
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

  Set<String> _overlappingIds() {
    final ids = <String>{};
    for (var i = 0; i < widget.slices.length; i++) {
      for (var j = i + 1; j < widget.slices.length; j++) {
        final a = widget.slices[i].slice;
        final b = widget.slices[j].slice;
        if (a.startAt.isBefore(b.endAt) && b.startAt.isBefore(a.endAt)) {
          ids.add(a.id);
          ids.add(b.id);
        }
      }
    }
    return ids;
  }
}

class _SliceBlock extends StatelessWidget {
  const _SliceBlock({
    required this.entry,
    required this.color,
    required this.isCurrent,
    required this.isNext,
    required this.overlaps,
    required this.onTap,
  });

  final DaySliceWithTask entry;
  final Color color;
  final bool isCurrent;
  final bool isNext;
  final bool overlaps;
  final VoidCallback onTap;

  static const Color _ink = Color(0xFF111318);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = DateFormat('HH:mm').format(entry.slice.startAt);
    final end = DateFormat('HH:mm').format(entry.slice.endAt);
    return Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: overlaps
            ? BorderSide(color: theme.colorScheme.error, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        key: Key('day-block-${entry.slice.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
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
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockTag extends StatelessWidget {
  const _BlockTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _SliceBlock._ink.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _SliceBlock._ink,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
