import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/entities/train_service.dart';
import 'package:train_yatri/features/train_details/train_details_screen.dart';

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

/// Both fixture trains (00101T overnight, 00102T same-day) live in
/// test/test_support/fake_railway_repository.dart's synthetic dataset -
/// the same one test/features/search/search_results_screen_test.dart
/// uses, so a fresh in-memory database each call assigns the same
/// deterministic IDs.
Future<TrainService> _lookupTrain(String number) async {
  final repository = await buildFakeRailwayRepository();
  return (await repository.getTrainByNumber(number))!;
}

void main() {
  testWidgets(
    'shows the train name, number and the historical-data disclosure',
    (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(_wrap(TrainDetailsScreen(train: train)));
      await tester.pumpAndSettle();

      expect(find.text('Test Overnight Express'), findsOneWidget);
      expect(find.textContaining('#00101T'), findsOneWidget);
      expect(
        find.textContaining('Schedule data is from Dec 2017'),
        findsOneWidget,
      );
      expect(find.textContaining('Operating days unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'renders the real ordered route: origin, intermediate stop, destination',
    (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(_wrap(TrainDetailsScreen(train: train)));
      await tester.pumpAndSettle();

      expect(find.textContaining('New Delta Alpha'), findsOneWidget);
      expect(find.textContaining('Junction Gamma'), findsOneWidget);
      expect(find.textContaining('Mumbai Central Beta'), findsOneWidget);
    },
  );

  testWidgets('marks the overnight stop with a +1d badge (day_offset, not '
      'raw clock time)', (tester) async {
    final train = await _lookupTrain('00101T');
    await tester.pumpWidget(_wrap(TrainDetailsScreen(train: train)));
    await tester.pumpAndSettle();

    expect(find.text('+1d'), findsOneWidget);
  });

  testWidgets('a same-day train shows no day-offset badge at all', (
    tester,
  ) async {
    final train = await _lookupTrain('00102T');
    await tester.pumpWidget(_wrap(TrainDetailsScreen(train: train)));
    await tester.pumpAndSettle();

    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets(
    'never shows any live/fabricated fields this dataset does not have',
    (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(_wrap(TrainDetailsScreen(train: train)));
      await tester.pumpAndSettle();

      for (final forbidden in [
        'Platform',
        'PNR',
        'Live',
        'Delay',
        'ETA',
        'Fare',
        'Running status',
        'Seat',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    },
  );

  testWidgets('the back button returns to the caller', (tester) async {
    final train = await _lookupTrain('00101T');
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TrainDetailsScreen(train: train),
                  ),
                ),
                child: const Text('open details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainDetailsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainDetailsScreen), findsNothing);
    expect(find.text('open details'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets('lays out without horizontal overflow at ${width}dp width', (
      tester,
    ) async {
      _useTallSurface(tester, width: width);
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(_wrap(TrainDetailsScreen(train: train)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
