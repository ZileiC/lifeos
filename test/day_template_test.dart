import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final template = File('assets/templates/day_timetable.html');
  final sample = File('assets/templates/sample_day.json');

  test('print template is a standalone A4 page with print CSS', () {
    final html = template.readAsStringSync();
    expect(html, contains('<!doctype html>'));
    expect(html, contains('@page'));
    expect(html, contains('size: A4 portrait'));
    expect(html, contains('@media print'));
    expect(html, contains('print-color-adjust: exact'));
    expect(html, contains('--hour: 9.6mm'));
    expect(html, contains('--radius: 2mm'));
    expect(html, contains('--label: 16mm'));
    expect(html, contains('border-left: 1.6pt'));
    expect(html, contains('const day = {'));
  });

  test('sample JSON is valid and matches the inline sample', () {
    final day = jsonDecode(sample.readAsStringSync()) as Map<String, dynamic>;
    expect(day['date'], '2026-11-04');
    final slices = (day['slices'] as List).cast<Map<String, dynamic>>();
    expect(slices, hasLength(8));
    for (final slice in slices) {
      expect(slice['taskId'], isA<String>());
      expect(slice['title'], isA<String>());
      expect(slice['color'] as String, matches(RegExp(r'^#[0-9A-Fa-f]{6}$')));
      expect(DateTime.tryParse(slice['startAt'] as String), isNotNull);
      expect(DateTime.tryParse(slice['endAt'] as String), isNotNull);
    }
    final html = template.readAsStringSync();
    for (final slice in slices) {
      expect(html, contains(slice['title'] as String));
      expect(html, contains(slice['color'] as String));
    }
  });

  test('the same task keeps the same color in the sample', () {
    final day = jsonDecode(sample.readAsStringSync()) as Map<String, dynamic>;
    final slices = (day['slices'] as List).cast<Map<String, dynamic>>();
    final reportColors = slices
        .where((slice) => slice['taskId'] == 'report')
        .map((slice) => slice['color'] as String)
        .toSet();
    expect(reportColors, hasLength(1));
  });

  test('template and docs carry the phone palette tokens', () {
    final html = template.readAsStringSync().toUpperCase();
    final docs = File('docs/day-template.md').readAsStringSync().toUpperCase();
    for (final color in const [
      '#7FA7C9',
      '#8FBFA8',
      '#D9B36C',
      '#C98A8A',
      '#9B8FC4',
      '#6FB7B7',
      '#C4A484',
      '#A8B56F',
      '#B78FB0',
      '#8E9EC4',
    ]) {
      expect(docs, contains(color));
    }
    expect(html, contains('#7FA7C9'));
    expect(html, contains('#6FB7B7'));
  });

  test('docs describe fields, A4 printing and OB usage', () {
    final docs = File('docs/day-template.md').readAsStringSync();
    expect(docs, contains('startAt'));
    expect(docs, contains('A4'));
    expect(docs, contains('OB'));
    expect(docs, contains('sample_day.json'));
    expect(docs, contains('背景图形'));
  });
}
