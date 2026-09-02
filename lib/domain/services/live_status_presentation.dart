import '../entities/live_train_status.dart';
import '../repositories/live_status_repository.dart';

/// What the Live Status screen actually renders - exhaustively switched
/// over (Dart 3 `sealed`) so a new state can never be added without the
/// UI being forced to handle it.
sealed class LiveStatusState {
  const LiveStatusState();
}

/// The very first fetch for this screen, still in flight - nothing to
/// show yet but a loading indicator.
final class LiveStatusLoading extends LiveStatusState {
  const LiveStatusLoading();
}

/// A real status is being shown. [isRefreshing] is true only for the
/// brief window a background poll is in flight while data is already
/// on screen (so the UI can show a subtle refresh indicator, not a
/// full-screen spinner). [isStale] is true when the most recent poll
/// failed but a real, previously-fetched status is still being shown
/// rather than being replaced by an error - the data itself is never
/// altered or guessed at, only its freshness is flagged.
final class LiveStatusAvailable extends LiveStatusState {
  const LiveStatusAvailable(
    this.status, {
    this.isRefreshing = false,
    this.isStale = false,
  });

  final LiveTrainStatus status;
  final bool isRefreshing;
  final bool isStale;

  LiveStatusAvailable copyWith({bool? isRefreshing, bool? isStale}) =>
      LiveStatusAvailable(
        status,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        isStale: isStale ?? this.isStale,
      );
}

/// No status could be shown at all (first load failed, or a poll
/// failed with no prior data to fall back on). [message] is always the
/// pre-written, safe string from [LiveStatusException] - never raw
/// backend/provider text.
final class LiveStatusUnavailable extends LiveStatusState {
  const LiveStatusUnavailable(this.category, this.message);

  final LiveStatusFailureCategory category;
  final String message;
}
