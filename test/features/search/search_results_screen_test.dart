import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/data/providers/running_days_lookup_providers.dart';
import 'package:train_yatri/domain/entities/station.dart';
import 'package:train_yatri/domain/repositories/running_days_lookup_repository.dart';
import 'package:train_yatri/features/search/search_results_screen.dart';
import 'package:train_yatri/features/train_details/train_details_screen.dart';

import '../../test_support/fake_railway_repository.dart';

const _nda = Station(stationId: 1, code: 'NDA', name: 'New Delta Alpha');
const _mcb = Station(stationId: 2, code: 'MCB', name: 'Mumbai Central Beta');
const _jxn = Station(stationId: 3, code: 'JXN', name: 'Junction Gamma');

/// Never confirms anything running - keeps Train Details tests below
/// deterministic and free of any real network attempt, since this
/// file isn't testing the running-days gate itself.
class _NeverConfirmsRunningDays implements RunningDaysLookupRepository {
  @override
  Future<Map<String, RunningDaysAnswer>> getRunningDays(
    List<String> trainNumbers,
  ) async => {
    for (final number in trainNumbers)
      number: const RunningDaysAnswer(RunningDaysLookupStatus.pending),
  };
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      fakeRailwayRepositoryOverride(),
      runningDaysLookupRepositoryProvider.overrideWithValue(
        _NeverConfirmsRunningDays(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows From/To codes and the selected date in the header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NDA'), findsOneWidget);
    expect(find.text('MCB'), findsOneWidget);
    expect(find.text('02 Sep, 2026'), findsOneWidget);
  });

  testWidgets('finds the real synthetic direct services between NDA and MCB', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('00101T'), findsOneWidget);
    expect(find.textContaining('00102T'), findsOneWidget);
  });

  testWidgets('marks the overnight service with a +1 day badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+1 day'), findsOneWidget);
  });

  testWidgets('shows an honest "no journey found" empty state when neither a '
      'direct service nor any connection exists', (tester) async {
    // JXN -> NDA: JXN is only ever an intermediate stop on trains
    // that continue on to MCB, never back to NDA - no direct service
    // and no connection legitimately exists for this pair.
    await tester.pumpWidget(
      _wrap(
        SearchResultsScreen(from: _jxn, to: _nda, date: DateTime(2026, 9, 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No journey found'), findsOneWidget);
  });

  testWidgets('the back button returns to the caller', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchResultsScreen(
                      from: _nda,
                      to: _mcb,
                      date: DateTime(2026, 9, 2),
                    ),
                  ),
                ),
                child: const Text('open results'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open results'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsScreen), findsNothing);
    expect(find.text('open results'), findsOneWidget);
  });

  testWidgets(
    'tapping a direct train result opens Train Details with the exact '
    'searched date - not today (regression: Live Status UI fix)',
    (tester) async {
      // A date that is never "today" in any real test run.
      final searchedDate = DateTime(2027, 3, 15);
      await tester.pumpWidget(
        _wrap(SearchResultsScreen(from: _nda, to: _mcb, date: searchedDate)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('00101T'));
      await tester.pumpAndSettle();

      final screen = tester.widget<TrainDetailsScreen>(
        find.byType(TrainDetailsScreen),
      );
      expect(screen.journeyDate, searchedDate);
      expect(screen.train.number, '00101T');
    },
  );
}
