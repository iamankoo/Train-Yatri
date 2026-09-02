import '../entities/recent_live_train.dart';

/// On-device storage for recently-viewed Live Status lookups. Mirrors
/// `RecentSearchesRepository` deliberately - same shape, same
/// on-device-only scope, same "not railway data" rationale.
abstract interface class RecentLiveTrainsRepository {
  /// Most-recently-viewed-first, at most [limit] entries.
  Future<List<RecentLiveTrain>> getRecent({int limit = 10});

  /// Records [train] as viewed just now. If [RecentLiveTrain.trainNumber]
  /// is already present, it is replaced (moved to the front) rather
  /// than duplicated.
  Future<void> save(RecentLiveTrain train);

  Future<void> clear();
}
