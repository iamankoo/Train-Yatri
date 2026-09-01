import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/recent_search.dart';
import '../../domain/repositories/recent_searches_repository.dart';
import '../repositories/shared_prefs_recent_searches_repository.dart';

final _sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

final recentSearchesRepositoryProvider =
    FutureProvider<RecentSearchesRepository>((ref) async {
      final preferences = await ref.watch(_sharedPreferencesProvider.future);
      return SharedPrefsRecentSearchesRepository(preferences);
    });

/// The list Home actually renders. Not `autoDispose`: Home is expected
/// to keep this around for the app's session. Call
/// `ref.invalidate(recentSearchesProvider)` after [RecentSearchesRepository.save]
/// so Home picks up the change (see `JourneySearchController`).
final recentSearchesProvider = FutureProvider<List<RecentSearch>>((ref) async {
  final repository = await ref.watch(recentSearchesRepositoryProvider.future);
  return repository.getRecent();
});
