import 'dart:ui';

import 'price_parser.dart';

enum ScanStatus { searching, checking, stable, needsConfirmation, fixed }

class PriceTracker {
  ScanStatus status = ScanStatus.searching;
  PriceCandidate? candidate;
  PriceAnalysis analysis = const PriceAnalysis();
  bool isLost = false;
  DateTime? _lastSeen;
  int _consecutive = 0;
  int _nextEventId = 0;
  ({int id, PriceCandidate price, DateTime seen})? _scene;

  int? get eventId {
    final scene = _scene;
    final price = candidate;
    return scene != null && price != null && _matches(scene.price, price)
        ? scene.id
        : null;
  }

  void observe(PriceAnalysis next, DateTime now) {
    if (status == ScanStatus.fixed) return;
    expire(now);
    final scene = _scene;
    if (scene != null &&
        now.difference(scene.seen) >= const Duration(seconds: 1)) {
      _scene = null;
    }
    final selected = next.selected;
    analysis = next;
    if (selected == null) {
      isLost = candidate != null;
      _consecutive = 0;
      expire(now);
      return;
    }
    final same = candidate != null && _matches(candidate!, selected);
    _consecutive = same ? _consecutive + 1 : 1;
    candidate = selected;
    _lastSeen = now;
    isLost = false;
    status = next.needsConfirmation
        ? ScanStatus.needsConfirmation
        : _consecutive >= 2
            ? ScanStatus.stable
            : ScanStatus.checking;
    if (eventId != null || status == ScanStatus.stable) {
      rememberScene(selected, now);
    }
  }

  int rememberScene(PriceCandidate price, DateTime now) {
    final scene = _scene;
    final id = scene != null && _matches(scene.price, price)
        ? scene.id
        : ++_nextEventId;
    _scene = (id: id, price: price, seen: now);
    return id;
  }

  void forgetScene() => _scene = null;

  void resumeAfterFix(DateTime now) {
    final scene = _scene;
    reset();
    if (scene != null) _scene = (id: scene.id, price: scene.price, seen: now);
  }

  void cancelEditing(DateTime now) {
    if (isLost || candidate == null || status == ScanStatus.fixed) return;
    _lastSeen = now;
    if (eventId != null) rememberScene(candidate!, now);
  }

  bool expire(DateTime now) {
    if (status == ScanStatus.fixed ||
        _lastSeen == null ||
        now.difference(_lastSeen!) < const Duration(seconds: 1)) return false;
    reset();
    return true;
  }

  void fix(PriceCandidate value) {
    candidate = value;
    status = ScanStatus.fixed;
    isLost = false;
  }

  void reset() {
    status = ScanStatus.searching;
    candidate = null;
    analysis = const PriceAnalysis();
    _lastSeen = null;
    _consecutive = 0;
    isLost = false;
    forgetScene();
  }
}

bool _matches(PriceCandidate a, PriceCandidate b) =>
    a.amountBani == b.amountBani &&
    a.unit == b.unit &&
    a.kind == b.kind &&
    _overlap(a.bounds, b.bounds) >= 0.5;

double _overlap(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) return 0;
  final area = intersection.width * intersection.height;
  final union = a.width * a.height + b.width * b.height - area;
  return union > 0 ? area / union : 0;
}
