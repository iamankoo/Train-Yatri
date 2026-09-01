// App-level smoke test: verifies the actual startup flow a user sees -
// splash screen first, then an automatic transition to Home after the
// ~3 second hold, landing on a Home screen that shows the real
// interactive search UI (not a placeholder).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:train_yatri/features/splash/splash_screen.dart';
import 'package:train_yatri/main.dart';

import 'test_support/fake_railway_repository.dart';

void main() {
  setUp(() {
    // RecentSearchesSection (rendered once Home appears) reads
    // shared_preferences, which has no platform channel under
    // flutter_test unless given mock initial values - without this its
    // loading state never resolves and pumpAndSettle hangs.
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrappedApp() => ProviderScope(
    overrides: [fakeRailwayRepositoryOverride()],
    child: const TrainYatriApp(),
  );

  testWidgets('shows the splash screen on launch', (tester) async {
    await tester.pumpWidget(wrappedApp());

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Search Trains'), findsNothing);

    // Avoid leaving the 3s timer pending when the test ends.
    await tester.pump(SplashScreen.holdDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('transitions from splash to Home after the hold duration', (
    tester,
  ) async {
    await tester.pumpWidget(wrappedApp());

    await tester.pump(SplashScreen.holdDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('Search Trains'), findsOneWidget);
  });
}
