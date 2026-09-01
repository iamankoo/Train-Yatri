import '../entities/recent_search.dart';

/// On-device storage for recent journey searches. Not railway data -
/// see `lib/data/repositories/shared_prefs_recent_searches_repository.dart`
/// for why this deliberately does not live in `railway.db`.
abstract interface class RecentSearchesRepository {
  /// Most-recent-first, at most [limit] entries.
  Future<List<RecentSearch>> getRecent({int limit = 10});

  /// Saves [search]. If a search for the same [RecentSearch.routeKey]
  /// already exists, it is replaced (moved to the front with the new
  /// date) rather than duplicated.
  Future<void> save(RecentSearch search);

  Future<void> clear();
}
