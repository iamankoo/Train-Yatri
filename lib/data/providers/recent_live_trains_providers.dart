import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/recent_live_train.dart';
import '../../domain/repositories/recent_live_trains_repository.dart';
import '../repositories/shared_prefs_recent_live_trains_repository.dart';

final _sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

final recentLiveTrainsRepositoryProvider =
    FutureProvider<RecentLiveTrainsRepository>((ref) async {
      final preferences = await ref.watch(_sharedPreferencesProvider.future);
      return SharedPrefsRecentLiveTrainsRepository(preferences);
    });

/// Call `ref.invalidate(recentLiveTrainsProvider)` after
/// [RecentLiveTrainsRepository.save] so the Live tab picks up the
/// change, mirroring `recentSearchesProvider`.
final recentLiveTrainsProvider = FutureProvider<List<RecentLiveTrain>>((
  ref,
) async {
  final repository = await ref.watch(recentLiveTrainsRepositoryProvider.future);
  return repository.getRecent();
});
