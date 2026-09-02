import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/recent_live_train.dart';
import '../../domain/repositories/recent_live_trains_repository.dart';

/// Stores recently-viewed Live Status lookups as a small JSON array
/// under one [SharedPreferences] key - mirrors
/// `SharedPrefsRecentSearchesRepository` deliberately. Most-recently-
/// viewed-first; viewing a train already present moves it to the front
/// rather than duplicating it.
class SharedPrefsRecentLiveTrainsRepository
    implements RecentLiveTrainsRepository {
  SharedPrefsRecentLiveTrainsRepository(this._preferences);

  final SharedPreferences _preferences;

  static const _storageKey = 'recent_live_trains_v1';
  static const _maxStored = 20;

  @override
  Future<List<RecentLiveTrain>> getRecent({int limit = 10}) async {
    return _readAll().take(limit).toList();
  }

  @override
  Future<void> save(RecentLiveTrain train) async {
    final stored = _readAll();
    stored.removeWhere((existing) => existing.trainNumber == train.trainNumber);
    stored.insert(0, train);
    final capped = stored.take(_maxStored).toList();
    await _preferences.setString(
      _storageKey,
      jsonEncode(capped.map((t) => t.toJson()).toList()),
    );
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_storageKey);
  }

  List<RecentLiveTrain> _readAll() {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => RecentLiveTrain.tryFromJson(e as Map<String, Object?>))
          .whereType<RecentLiveTrain>()
          .toList();
    } on FormatException {
      return [];
    }
  }
}
