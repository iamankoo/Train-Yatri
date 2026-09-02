import '../entities/live_train_status.dart';

/// Category of failure fetching live status - lets the UI pick the right
/// safe, fixed message (Block 6 Part 25/26) without ever seeing the
/// backend's raw error text.
enum LiveStatusFailureCategory {
  notFound,
  rateLimited,
  providerUnavailable,
  notConfigured,
  network,
  timeout,
  unknown,
}

/// Thrown by [LiveStatusRepository] implementations. [message] is always
/// a pre-written, safe, user-displayable string - never raw
/// backend/provider text.
class LiveStatusException implements Exception {
  const LiveStatusException(this.category, this.message);

  final LiveStatusFailureCategory category;
  final String message;

  @override
  String toString() => 'LiveStatusException($category, $message)';
}

/// The only way the Flutter app reaches live train data. The concrete
/// implementation talks exclusively to the Train Yatri backend - never
/// to RailRadar directly - so this interface's shape is deliberately
/// backend-facing rather than provider-facing.
abstract interface class LiveStatusRepository {
  /// Fetches the current live status for [trainNumber]. [journeyDate],
  /// when given, is passed through as `YYYY-MM-DD`.
  ///
  /// Throws [LiveStatusException] on any failure - never returns a
  /// simulated/fabricated status.
  Future<LiveTrainStatus> getLiveStatus(
    String trainNumber, {
    String? journeyDate,
  });
}
