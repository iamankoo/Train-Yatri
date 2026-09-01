import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:train_yatri/core/routing/app_router.dart';
import 'package:train_yatri/core/routing/app_routes.dart';
import 'package:train_yatri/features/splash/splash_screen.dart';

import '../../test_support/fake_railway_repository.dart';

void main() {
  setUp(() {
    // This test navigates all the way to Home, whose
    // RecentSearchesSection reads shared_preferences - which has no
    // platform channel under flutter_test unless given mock initial
    // values, otherwise its loading state never resolves and
    // pumpAndSettle hangs.
    SharedPreferences.setMockInitialValues({});
  });

  test('holds for exactly 3 seconds', () {
    expect(SplashScreen.holdDuration, const Duration(seconds: 3));
  });

  testWidgets('shows the full splash artwork undistorted (BoxFit.contain)', (
    tester,
  ) async {
    // Routed through the real app router (rather than a bare
    // MaterialApp(home:...)) so the splash-to-home navigation the
    // widget performs after the hold duration has somewhere to go.
    // ProviderScope is required now that SplashScreen pre-warms
    // railwayRepositoryProvider on init - overridden with the fake
    // in-memory repository so this test never touches the real
    // platform-channel database.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fakeRailwayRepositoryOverride()],
        child: MaterialApp(
          initialRoute: AppRoutes.splash,
          onGenerateRoute: AppRouter.generateRoute,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);

    // Avoid leaving the 3s navigation timer pending when the test ends.
    await tester.pump(SplashScreen.holdDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
