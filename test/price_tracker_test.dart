import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/scanner/frame_gate.dart';
import 'package:pricelens/scanner/price_parser.dart';
import 'package:pricelens/scanner/price_tracker.dart';

void main() {
  final start = DateTime.utc(2026, 11, 3);
  PriceAnalysis reading(String text, {double left = 0}) =>
      const PriceParser().analyze([
        OcrLine(text, Rect.fromLTWH(left, 0, 100, 40)),
      ]);

  test('Two consistent observations produce a stable price', () {
    final tracker = PriceTracker();
    tracker.observe(reading('24,99 RON'), start);
    expect(tracker.status, ScanStatus.checking);
    tracker.observe(
        reading('24,99 RON'), start.add(const Duration(milliseconds: 200)));
    expect(tracker.status, ScanStatus.stable);
    expect(tracker.candidate?.amountBani, 2499);
  });

  test('A new value or distant label must stabilise again', () {
    final tracker = PriceTracker();
    tracker.observe(reading('24,99 RON'), start);
    tracker.observe(reading('24,99 RON'), start);
    tracker.observe(reading('19,99 RON'), start);
    expect(tracker.status, ScanStatus.checking);
    tracker.observe(reading('19,99 RON', left: 300), start);
    expect(tracker.status, ScanStatus.checking);
  });

  test('Lost price expires without waiting for another camera frame', () {
    final tracker = PriceTracker();
    tracker.observe(reading('24,99 RON'), start);
    tracker.observe(reading('24,99 RON'), start);
    tracker.expire(start.add(const Duration(seconds: 1)));
    expect(tracker.candidate, isNull);
    expect(tracker.status, ScanStatus.searching);
  });

  test('Repeated ambiguous observations never become confident', () {
    final tracker = PriceTracker();
    for (var i = 0; i < 10; i++) {
      tracker.observe(reading('19,98 LEI/kg'), start);
    }
    expect(tracker.status, ScanStatus.needsConfirmation);
  });

  test(
      'An established scene survives a brief disappearance and one wrong frame',
      () {
    final tracker = PriceTracker();
    final original = reading('24,99 RON');
    tracker.observe(original, start);
    tracker.observe(original, start.add(const Duration(milliseconds: 200)));
    final event = tracker.eventId;
    expect(event, isNotNull);
    tracker.observe(
        const PriceAnalysis(), start.add(const Duration(milliseconds: 400)));
    tracker.observe(
        reading('24,89 RON'), start.add(const Duration(milliseconds: 600)));
    tracker.observe(original, start.add(const Duration(milliseconds: 800)));
    tracker.observe(original, start.add(const Duration(milliseconds: 900)));
    expect(tracker.eventId, event);

    tracker.observe(
        const PriceAnalysis(), start.add(const Duration(milliseconds: 1900)));
    tracker.observe(original, start.add(const Duration(milliseconds: 2000)));
    tracker.observe(original, start.add(const Duration(milliseconds: 2200)));
    expect(tracker.eventId, isNot(event));
  });

  test('Continuing after a correction keeps the original OCR scene identity',
      () {
    final tracker = PriceTracker();
    final original = reading('24,99 RON');
    tracker.observe(original, start);
    tracker.observe(original, start);
    final event = tracker.eventId;
    tracker.fix(reading('23,99 RON').selected!);
    final resumed = start.add(const Duration(minutes: 1));
    tracker.resumeAfterFix(resumed);
    tracker.observe(original, resumed);
    tracker.observe(original, resumed);
    expect(tracker.eventId, event);
    tracker.observe(reading('24,99 RON', left: 300), resumed);
    tracker.observe(reading('24,99 RON', left: 300), resumed);
    expect(tracker.eventId, isNot(event));
  });

  test('Fixed result survives timeout until scanning resumes', () {
    final tracker = PriceTracker();
    tracker.fix(reading('24,99 RON').selected!);
    tracker.expire(start.add(const Duration(hours: 1)));
    tracker.observe(reading('19,99 RON'), start);
    expect(tracker.candidate?.amountBani, 2499);
    tracker.reset();
    expect(tracker.candidate, isNull);
  });

  test('Frame gate limits concurrency and frequency, rejects stale results',
      () {
    final gate = FrameGate();
    final ticket = gate.tryBegin(start)!;
    expect(gate.tryBegin(start.add(const Duration(seconds: 1))), isNull);
    gate.invalidate();
    expect(gate.tryBegin(start.add(const Duration(seconds: 2))), isNull);
    expect(gate.finish(ticket), isFalse);
    final next = gate.tryBegin(start.add(const Duration(seconds: 2)))!;
    expect(gate.finish(next), isTrue);
    expect(
        gate.tryBegin(start.add(const Duration(milliseconds: 2100))), isNull);
    expect(gate.tryBegin(start.add(const Duration(milliseconds: 2200))),
        isNotNull);
  });
}
