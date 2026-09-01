import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/recent_search.dart';
import '../../domain/repositories/recent_searches_repository.dart';

/// Stores recent searches as a small JSON array under one
/// [SharedPreferences] key - deliberately not in `railway.db` (see the
/// abstract interface for why). Most-recent-first; a new search for a
/// route already present replaces the old entry rather than
/// duplicating it.
class SharedPrefsRecentSearchesRepository implements RecentSearchesRepository {
  SharedPrefsRecentSearchesRepository(this._preferences);

  final SharedPreferences _preferences;

  static const _storageKey = 'recent_searches_v1';

  /// Hard cap on how many are ever kept on disk, independent of what a
  /// caller asks [getRecent] to return.
  static const _maxStored = 20;

  @override
  Future<List<RecentSearch>> getRecent({int limit = 10}) async {
    final stored = _readAll();
    return stored.take(limit).toList();
  }

  @override
  Future<void> save(RecentSearch search) async {
    final stored = _readAll();
    stored.removeWhere((existing) => existing.routeKey == search.routeKey);
    stored.insert(0, search);
    final capped = stored.take(_maxStored).toList();
    await _preferences.setString(
      _storageKey,
      jsonEncode(capped.map((s) => s.toJson()).toList()),
    );
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_storageKey);
  }

  List<RecentSearch> _readAll() {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => RecentSearch.tryFromJson(e as Map<String, Object?>))
          .whereType<RecentSearch>()
          .toList();
    } on FormatException {
      // Corrupt/unexpected stored value - treat as empty rather than
      // crashing Home on every launch.
      return [];
    }
  }
}
