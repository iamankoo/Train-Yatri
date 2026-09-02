/// Minimal "Xh YYm" duration formatting - shared between direct-service
/// cards and connecting-journey cards (Block 5) so both render a
/// journey duration/wait time identically.
abstract final class DurationFormatter {
  static String hoursMinutes(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  /// Compact form for a short wait ("Wait 42 min") rather than a full
  /// journey duration - drops the hours component entirely under an
  /// hour, per Block 5's "display compactly" requirement.
  static String compactMinutes(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = duration.inHours;
    final minutes = totalMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
}
