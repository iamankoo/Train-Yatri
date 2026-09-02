/// What is actually known about a train's weekly running days, from
/// the Train Yatri backend's progressive RailRadar-backed lookup (see
/// `docs/RUNNING_DAYS_BACKFILL.md`) - distinct from the local, mostly-
/// empty `running_days` SQLite table (`RunningDays`/`DataConfidence`),
/// which this deliberately does not touch or extend.
enum RunningDaysLookupStatus {
  /// A real weekly calendar was returned by RailRadar and is available
  /// in [RunningDaysAnswer.days].
  confirmed,

  /// RailRadar was asked and explicitly had no running-days data for
  /// this train - a real answer, just an empty one. Distinct from
  /// [pending] so a caller never keeps re-asking for a train that is
  /// already known to have no data.
  noData,

  /// Not yet known - either never looked up, or the backend chose not
  /// to spend RailRadar quota on it this time (Live Status always has
  /// priority for the shared quota). Callers must treat this exactly
  /// like "no information", never as an error.
  pending,
}

final class RunningDaysAnswer {
  const RunningDaysAnswer(this.status, {this.days});

  final RunningDaysLookupStatus status;

  /// Keyed by lowercase day name (`monday`..`sunday`). Non-null only
  /// when [status] is [RunningDaysLookupStatus.confirmed].
  final Map<String, bool>? days;

  /// Whether the train is confirmed to run on [weekday] (per
  /// `DateTime.weekday`, 1 = Monday .. 7 = Sunday). Only meaningful
  /// when [status] is [RunningDaysLookupStatus.confirmed] - callers
  /// must check that first.
  bool operatesOnWeekday(int weekday) {
    const keys = {
      DateTime.monday: 'monday',
      DateTime.tuesday: 'tuesday',
      DateTime.wednesday: 'wednesday',
      DateTime.thursday: 'thursday',
      DateTime.friday: 'friday',
      DateTime.saturday: 'saturday',
      DateTime.sunday: 'sunday',
    };
    return days?[keys[weekday]] ?? false;
  }
}

/// Best-effort, progressive weekly-running-days lookup by train
/// number, backed by the Train Yatri backend (never RailRadar
/// directly, never the app's own credential-free key-less state).
/// Purely additive to Journey Search - a failure here must never break
/// or slow down the offline, always-available core search.
abstract interface class RunningDaysLookupRepository {
  /// Looks up [trainNumbers] (a real search result's worth, not the
  /// whole database) in one batched call. Never throws: on any
  /// failure (offline, backend unreachable, timeout) this resolves to
  /// an empty map, meaning "nothing learned this time" - callers must
  /// treat a missing key exactly like [RunningDaysLookupStatus.pending].
  Future<Map<String, RunningDaysAnswer>> getRunningDays(
    List<String> trainNumbers,
  );
}
