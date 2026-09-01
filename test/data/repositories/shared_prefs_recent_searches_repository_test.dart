import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:train_yatri/data/repositories/shared_prefs_recent_searches_repository.dart';
import 'package:train_yatri/domain/entities/recent_search.dart';

RecentSearch _search({
  required String from,
  required String to,
  DateTime? date,
  DateTime? searchedAt,
}) {
  return RecentSearch(
    fromCode: from,
    fromName: '$from Station',
    toCode: to,
    toName: '$to Station',
    date: date ?? DateTime(2026, 9, 2),
    searchedAt: searchedAt ?? DateTime(2026, 9, 2, 10),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh install has no recent searches', () async {
    final repository = SharedPrefsRecentSearchesRepository(
      await SharedPreferences.getInstance(),
    );
    expect(await repository.getRecent(), isEmpty);
  });

  test('save then getRecent round-trips a search', () async {
    final repository = SharedPrefsRecentSearchesRepository(
      await SharedPreferences.getInstance(),
    );
    await repository.save(_search(from: 'NDA', to: 'MCB'));

    final result = await repository.getRecent();
    expect(result, hasLength(1));
    expect(result.single.fromCode, 'NDA');
    expect(result.single.toCode, 'MCB');
  });

  test('most recent search is first', () async {
    final repository = SharedPrefsRecentSearchesRepository(
      await SharedPreferences.getInstance(),
    );
    await repository.save(
      _search(from: 'A', to: 'B', searchedAt: DateTime(2026, 1, 1)),
    );
    await repository.save(
      _search(from: 'C', to: 'D', searchedAt: DateTime(2026, 1, 2)),
    );

    final result = await repository.getRecent();
    expect(result.map((s) => s.routeKey), ['C>D', 'A>B']);
  });

  test(
    'saving the same route again replaces the old entry rather than duplicating it',
    () async {
      final repository = SharedPrefsRecentSearchesRepository(
        await SharedPreferences.getInstance(),
      );
      await repository.save(
        _search(from: 'NDA', to: 'MCB', date: DateTime(2026, 1, 1)),
      );
      await repository.save(
        _search(from: 'NDA', to: 'MCB', date: DateTime(2026, 6, 1)),
      );

      final result = await repository.getRecent();
      expect(result, hasLength(1));
      expect(result.single.date, DateTime(2026, 6, 1));
    },
  );

  test('getRecent respects the limit parameter', () async {
    final repository = SharedPrefsRecentSearchesRepository(
      await SharedPreferences.getInstance(),
    );
    for (var i = 0; i < 5; i++) {
      await repository.save(_search(from: 'S$i', to: 'T$i'));
    }
    expect(await repository.getRecent(limit: 2), hasLength(2));
  });

  test('storage is capped even beyond what getRecent asks for', () async {
    final repository = SharedPrefsRecentSearchesRepository(
      await SharedPreferences.getInstance(),
    );
    for (var i = 0; i < 25; i++) {
      await repository.save(_search(from: 'S$i', to: 'T$i'));
    }
    expect(await repository.getRecent(limit: 100), hasLength(20));
  });

  test('clear empties the store', () async {
    final repository = SharedPrefsRecentSearchesRepository(
      await SharedPreferences.getInstance(),
    );
    await repository.save(_search(from: 'NDA', to: 'MCB'));
    await repository.clear();
    expect(await repository.getRecent(), isEmpty);
  });

  test('a corrupt stored value is treated as empty, not a crash', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('recent_searches_v1', 'not valid json{{{');
    final repository = SharedPrefsRecentSearchesRepository(preferences);
    expect(await repository.getRecent(), isEmpty);
  });
}
