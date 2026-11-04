/// Keeps one native OCR call in flight, including across camera sessions.
class FrameGate {
  int _generation = 0;
  bool _busy = false;
  DateTime? _lastStarted;

  int? tryBegin(DateTime now) {
    if (_busy ||
        (_lastStarted != null &&
            now.difference(_lastStarted!) <
                const Duration(milliseconds: 200))) {
      return null;
    }
    _busy = true;
    _lastStarted = now;
    return _generation;
  }

  bool finish(int ticket) {
    _busy = false;
    return ticket == _generation;
  }

  void invalidate() {
    _generation++;
    _lastStarted = null;
  }
}
