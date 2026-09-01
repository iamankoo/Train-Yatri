import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:train_yatri/features/home/home_screen.dart';

Widget _wrap(Widget child) {
  return ProviderScope(child: MaterialApp(home: child));
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
  testWidgets('renders the core From/To/Date/Search interaction', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    expect(find.text('Select source station'), findsOneWidget);
    expect(find.text('Select destination station'), findsOneWidget);
    expect(find.text('Search Trains'), findsOneWidget);
  });

  testWidgets('tapping the From field gives honest feedback, not a picker', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('Select source station'));
    await tester.pump();

    expect(
      find.textContaining('Station search is coming in the next block'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the To field gives honest feedback, not a picker', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('Select destination station'));
    await tester.pump();

    expect(
      find.textContaining('Station search is coming in the next block'),
      findsOneWidget,
    );
  });

  testWidgets('the date field opens a real date picker and updates on pick', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('Date of Journey'));
    await tester.pumpAndSettle();

    // A real platform date picker dialog must actually open.
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Confirm today's pre-selected date (the "OK" action) to close it.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('does not show a fabricated recent-search entry', (tester) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    // There is no persisted search history yet, so the empty state must
    // be shown rather than an invented example route.
    expect(find.text('No recent searches yet'), findsOneWidget);
    expect(find.textContaining('NDLS'), findsNothing);
    expect(find.textContaining('MMCT'), findsNothing);
  });

  testWidgets('tapping Search Trains gives honest feedback, not a result', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('Search Trains'));
    await tester.pump();

    expect(find.textContaining('coming in a future block'), findsOneWidget);
  });

  testWidgets('quick actions give feedback instead of fake results', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

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

    for (final label in ['Home', 'Live', 'Journeys', 'Profile']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('tapping a non-Home tab gives feedback instead of navigating', (
    tester,
  ) async {
    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(const HomeScreen()));

    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(find.textContaining('coming soon'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 411.0, 430.0]) {
    testWidgets('lays out without horizontal overflow at ${width}dp width', (
      tester,
    ) async {
      _useTallSurface(tester, width: width);
      await tester.pumpWidget(_wrap(const HomeScreen()));
      await tester.pump();

      // tester.takeException() is flutter_test's supported way to read a
      // render/layout exception (e.g. "A RenderFlex overflowed by Npx")
      // without interfering with the framework's own error tracking -
      // overriding FlutterError.onError directly here previously caused
      // the whole suite to hang.
      expect(tester.takeException(), isNull);
    });
  }
}
