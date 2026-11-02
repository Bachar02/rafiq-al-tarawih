/// Exponential backoff for reconnecting: 0.5 s, 1 s, 2 s, 4 s, 8 s, 8 s, ...
Duration backoffDelay(
  int attempt, {
  Duration base = const Duration(milliseconds: 500),
  Duration max = const Duration(seconds: 8),
}) {
  if (attempt < 1) return Duration.zero;
  final factor = 1 << (attempt - 1).clamp(0, 20);
  final delay = base * factor;
  return delay > max ? max : delay;
}
