import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/data/providers/running_days_lookup_providers.dart';
import 'package:train_yatri/domain/entities/station.dart';
import 'package:train_yatri/domain/repositories/running_days_lookup_repository.dart';
import 'package:train_yatri/features/search/search_results_screen.dart';

import '../../test_support/fake_railway_repository.dart';

const _nda = Station(stationId: 1, code: 'NDA', name: 'New Delta Alpha');
const _mcb = Station(stationId: 2, code: 'MCB', name: 'Mumbai Central Beta');

final _allDaysTrue = {
  for (final day in [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ])
    day: true,
};

class _FakeRunningDaysLookupRepository implements RunningDaysLookupRepository {
  _FakeRunningDaysLookupRepository(this.answers);

  final Map<String, RunningDaysAnswer> answers;
  List<String>? lastRequested;

  @override
  Future<Map<String, RunningDaysAnswer>> getRunningDays(
    List<String> trainNumbers,
  ) async {
    lastRequested = trainNumbers;
    return answers;
  }
}

Widget _wrap(Widget child, RunningDaysLookupRepository repository) {
  return ProviderScope(
    overrides: [
      fakeRailwayRepositoryOverride(),
      runningDaysLookupRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
    'splits confirmed-running trains into a dated section above the full list',
    (tester) async {
      final repository = _FakeRunningDaysLookupRepository({
        '00102T': RunningDaysAnswer(
          RunningDaysLookupStatus.confirmed,
          days: _allDaysTrue,
        ),
      });

      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
          repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Running on'), findsOneWidget);
      expect(find.text('All Direct Trains'), findsOneWidget);
      // The confirmed train appears in both the dated section and the
      // complete list below it - never removed from the full list.
      expect(find.textContaining('00102T'), findsNWidgets(2));
      // The other train (no confirmed answer) appears only once, in
      // the complete list.
      expect(find.textContaining('00101T'), findsOneWidget);

      expect(repository.lastRequested, containsAll(['00101T', '00102T']));
    },
  );

  testWidgets(
    'shows a single unsplit Direct section when nothing is confirmed',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
          _FakeRunningDaysLookupRepository(const {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Direct'), findsOneWidget);
      expect(find.textContaining('Running on'), findsNothing);
      expect(find.text('All Direct Trains'), findsNothing);
      expect(find.textContaining('00101T'), findsOneWidget);
      expect(find.textContaining('00102T'), findsOneWidget);
    },
  );

  testWidgets(
    'a train confirmed NOT to run that weekday stays in the full list, unsplit-out',
    (tester) async {
      final repository = _FakeRunningDaysLookupRepository({
        '00102T': const RunningDaysAnswer(
          RunningDaysLookupStatus.confirmed,
          days: {
            'monday': false,
            'tuesday': false,
            'wednesday': false,
            'thursday': false,
            'friday': false,
            'saturday': false,
            'sunday': false,
          },
        ),
      });

      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
          repository,
        ),
      );
      await tester.pumpAndSettle();

      // Nothing confirmed to run that day -> no dated section at all.
      expect(find.textContaining('Running on'), findsNothing);
      expect(find.text('Direct'), findsOneWidget);
      expect(find.textContaining('00102T'), findsOneWidget);
    },
  );
}
