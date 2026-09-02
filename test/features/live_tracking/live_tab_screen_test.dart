import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:train_yatri/domain/entities/live_train_status.dart';
import 'package:train_yatri/domain/repositories/live_status_repository.dart';
import 'package:train_yatri/features/live_tracking/live_status_controller.dart';
import 'package:train_yatri/features/live_tracking/live_status_screen.dart';
import 'package:train_yatri/features/live_tracking/live_tab_screen.dart';

class _NeverRespondingRepository implements LiveStatusRepository {
  @override
  Future<LiveTrainStatus> getLiveStatus(
    String trainNumber, {
    String? journeyDate,
  }) {
    // Deliberately fails fast (never hangs) rather than never
    // resolving, so a test that reaches LiveStatusScreen never leaves
    // a pending Future behind.
    return Future.error(
      const LiveStatusException(
        LiveStatusFailureCategory.notFound,
        "Live status isn't available for this train.",
      ),
    );
  }
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      liveStatusRepositoryProvider.overrideWithValue(
        _NeverRespondingRepository(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows an empty state when nothing has been viewed yet', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const LiveTabScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No recently viewed trains yet'), findsOneWidget);
  });

  testWidgets('rejects a non-numeric train number without navigating', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const LiveTabScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();

    expect(find.text('Enter a valid train number'), findsOneWidget);
    expect(find.byType(LiveStatusScreen), findsNothing);
  });

  testWidgets('a valid train number navigates to Live Status', (tester) async {
    await tester.pumpWidget(_wrap(const LiveTabScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '12951');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(LiveStatusScreen), findsOneWidget);
  });

  testWidgets('a saved recent train appears and reopens Live Status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'recent_live_trains_v1':
          '[{"trainNumber":"12951","trainName":"Test Rajdhani","viewedAt":"2026-09-02T10:00:00.000Z"}]',
    });

    await tester.pumpWidget(_wrap(const LiveTabScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Test Rajdhani'), findsOneWidget);
    expect(find.text('#12951'), findsOneWidget);

    await tester.tap(find.text('Test Rajdhani'));
    await tester.pumpAndSettle();

    expect(find.byType(LiveStatusScreen), findsOneWidget);
  });
}
