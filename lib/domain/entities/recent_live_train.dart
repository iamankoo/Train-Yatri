/// A previously-viewed Live Status lookup, kept locally on-device so
/// the user can quickly reopen it. Deliberately lightweight - only the
/// train number/name and when it was viewed. No live status data, no
/// backend/provider details, and nothing credential-bearing is ever
/// stored here (Block 6 Part 28).
final class RecentLiveTrain {
  const RecentLiveTrain({
    required this.trainNumber,
    required this.trainName,
    required this.viewedAt,
  });

  final String trainNumber;

  /// The name at the time it was last viewed - may go stale if RailRadar
  /// later reports a different name, which is fine: this is only a
  /// convenience label for re-opening the lookup, not live data.
  final String? trainName;

  final DateTime viewedAt;

  Map<String, Object?> toJson() => {
    'trainNumber': trainNumber,
    'trainName': trainName,
    'viewedAt': viewedAt.toIso8601String(),
  };

  static RecentLiveTrain? tryFromJson(Map<String, Object?> json) {
    final trainNumber = json['trainNumber'] as String?;
    final viewedAt = DateTime.tryParse(json['viewedAt'] as String? ?? '');
    if (trainNumber == null || viewedAt == null) return null;
    return RecentLiveTrain(
      trainNumber: trainNumber,
      trainName: json['trainName'] as String?,
      viewedAt: viewedAt,
    );
  }
}
