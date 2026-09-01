import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/entities/station.dart';
import 'package:train_yatri/features/search/search_results_screen.dart';

import '../../test_support/fake_railway_repository.dart';

const _nda = Station(stationId: 1, code: 'NDA', name: 'New Delta Alpha');
const _mcb = Station(stationId: 2, code: 'MCB', name: 'Mumbai Central Beta');
const _jxn = Station(stationId: 3, code: 'JXN', name: 'Junction Gamma');

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [fakeRailwayRepositoryOverride()],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows the historical-data notice on every result screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SearchResultsScreen(from: _nda, to: _mcb, date: DateTime(2026, 9, 2)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Schedule data is from Dec 2017'),
      findsOneWidget,
    );
  });

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

  testWidgets(
    'shows an honest empty state for a route with no direct service',
    (tester) async {
      // JXN -> NDA: JXN is only ever an intermediate stop, never followed
      // by NDA later in either synthetic route, so no direct service
      // legitimately exists for this pair.
      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: _jxn, to: _nda, date: DateTime(2026, 9, 2)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No direct trains found'), findsOneWidget);
    },
  );

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
}
