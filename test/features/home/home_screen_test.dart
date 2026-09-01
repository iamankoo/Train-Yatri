import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:train_yatri/features/home/home_screen.dart';
import 'package:train_yatri/features/search/search_results_screen.dart';
import 'package:train_yatri/features/search/station_picker_screen.dart';

import '../../test_support/fake_railway_repository.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [fakeRailwayRepositoryOverride()],
    child: MaterialApp(home: child),
  );
}

/// The full Home content is taller than the default 800x600 test surface,
/// so a normal ListView only builds what would be on-screen. Growing the
/// surface lets every section (including the ones below the fold on a
/// real phone) render and hit-test without needing scrollUntilVisible
/// in every test.
void _useTallSurface(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    // Recent searches use shared_preferences, which has no platform
    // channel under flutter_test unless given mock initial values -
    // without this, RecentSearchesSection's loading state never
    // resolves and pumpAndSettle hangs.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the core From/To/Date/Search interaction', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Select source station'), findsOneWidget);
    expect(find.text('Select destination station'), findsOneWidget);
    expect(find.text('Search Trains'), findsOneWidget);
  });

  testWidgets('tapping From opens the real station picker', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select source station'));
    await tester.pumpAndSettle();

    expect(find.byType(StationPickerScreen), findsOneWidget);
  });

  testWidgets('searching and selecting a real station fills the From field', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select source station'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'New Delta');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();

    expect(find.text('New Delta Alpha'), findsOneWidget);
    await tester.tap(find.text('New Delta Alpha'));
    await tester.pumpAndSettle();

    // Back on Home, with the real selected station shown.
    expect(find.byType(StationPickerScreen), findsNothing);
    expect(find.textContaining('New Delta Alpha (NDA)'), findsOneWidget);
  });

  testWidgets(
    'tapping Search Trains without stations selected shows a validation message, not a fake result',
    (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search Trains'));
      await tester.pump();

      expect(
        find.text('Select both From and To stations to search.'),
        findsOneWidget,
      );
      expect(find.byType(SearchResultsScreen), findsNothing);
    },
  );

  testWidgets(
    'a full From/To selection then Search Trains opens real results',
    (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select source station'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'NDA');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Delta Alpha'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select destination station'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'MCB');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mumbai Central Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search Trains'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      // Real synthetic services, found via the real repository - not
      // fabricated in the widget layer.
      expect(find.textContaining('00101T'), findsOneWidget);
      expect(find.textContaining('00102T'), findsOneWidget);
    },
  );

  testWidgets('does not show a fabricated recent-search entry', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    // There is no persisted search history yet, so the empty state must
    // be shown rather than an invented example route.
    expect(find.text('No recent searches yet'), findsOneWidget);
    expect(find.textContaining('NDLS'), findsNothing);
    expect(find.textContaining('MMCT'), findsNothing);
  });

  testWidgets('the date field opens a real date picker and updates on pick', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Date of Journey'));
    await tester.pumpAndSettle();

    // A real platform date picker dialog must actually open.
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Confirm today's pre-selected date (the "OK" action) to close it.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('quick actions give feedback instead of fake results', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    for (final label in [
      'Live Status',
      'PNR Status',
      'Station Search',
      'Book Tickets',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('PNR Status'));
    await tester.pump();
    expect(find.textContaining('PNR Status is coming soon'), findsOneWidget);
  });

  testWidgets('shows the Home/Live/Journeys/Profile navigation shell', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    for (final label in ['Home', 'Live', 'Journeys', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('tapping a non-Home tab gives feedback instead of navigating', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(find.textContaining('coming soon'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets('lays out without horizontal overflow at ${width}dp width', (
      tester,
    ) async {
      _useTallSurface(tester, width: width);
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      // tester.takeException() is flutter_test's supported way to read a
      // render/layout exception (e.g. "A RenderFlex overflowed by Npx")
      // without interfering with the framework's own error tracking -
      // overriding FlutterError.onError directly here previously caused
      // the whole suite to hang.
      expect(tester.takeException(), isNull);
    });
  }
}
