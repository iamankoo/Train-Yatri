// Block 4, C8: "Profile" in the bottom nav now opens the real (if
// deliberately minimal) ProfileScreen instead of a "coming soon" snackbar
// - kept in its own file so home_screen_test.dart's broader nav-shell
// tests don't need to know about the update system ProfileScreen pulls
// in.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:train_yatri/features/home/home_screen.dart';
import 'package:train_yatri/features/profile/profile_screen.dart';

import '../../test_support/fake_railway_repository.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [fakeRailwayRepositoryOverride()],
    child: MaterialApp(home: child),
  );
}

void _useTallSurface(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping Profile opens the real ProfileScreen', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
  });
}
