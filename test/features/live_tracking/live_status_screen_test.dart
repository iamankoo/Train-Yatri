import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:train_yatri/domain/entities/live_train_status.dart';
import 'package:train_yatri/domain/repositories/live_status_repository.dart';
import 'package:train_yatri/features/live_tracking/live_status_controller.dart';
import 'package:train_yatri/features/live_tracking/live_status_screen.dart';

LiveTrainStatus _status({
  int? delayMinutes,
  LiveCurrentLocation? currentLocation,
  List<LiveRouteStop> route = const [],
  List<LiveException> exceptions = const [],
}) => LiveTrainStatus(
  trainNumber: '12951',
  trainName: 'Test Rajdhani',
  journeyDate: '2026-09-02',
  status: LiveStatusCategory.running,
  delayMinutes: delayMinutes,
  lastUpdatedAt: DateTime(2026, 9, 2, 10, 30),
  isLive: true,
  currentLocation: currentLocation,
  previousHalt: null,
  nextHalt: const LiveHalt(
    stationCode: 'RTM',
    stationName: 'Ratlam',
    sequence: 5,
    distanceKm: 520,
  ),
  route: route,
  exceptions: exceptions,
);

class _StubRepository implements LiveStatusRepository {
  _StubRepository(this._result);

  final Object _result; // LiveTrainStatus or LiveStatusException

  @override
  Future<LiveTrainStatus> getLiveStatus(
    String trainNumber, {
    String? journeyDate,
  }) async {
    final result = _result;
    if (result is LiveStatusException) throw result;
    return result as LiveTrainStatus;
  }
}

Widget _wrap(Widget child, LiveStatusRepository repository) {
  return ProviderScope(
    overrides: [liveStatusRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(home: child),
  );
}

/// A bounded stand-in for `pumpAndSettle()`: the live delay indicator
/// pulses forever by design (Block 6 UI fix, Part 5), so
/// `pumpAndSettle` never returns while one is on screen. This pumps
/// enough frames to flush the real async fetch and any page-route
/// transition without waiting on an animation that never stops.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a loading indicator before the first fetch resolves', (
    tester,
  ) async {
    final repository = _StubRepository(_status());
    await tester.pumpWidget(
      _wrap(const LiveStatusScreen(trainNumber: '12951'), repository),
    );

    // Deliberately no pump() between pumpWidget and this assertion:
    // the controller's state is synchronously LiveStatusLoading at
    // construction, before the (already-async) fetch's continuation
    // has had a chance to run.
    expect(find.text('Loading live status...'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('renders status, delay, current location and next halt', (
    tester,
  ) async {
    final repository = _StubRepository(
      _status(
        delayMinutes: 12,
        currentLocation: const LiveCurrentLocation(
          stationCode: 'BRC',
          sequence: 4,
          status: 'departed',
          isHalt: false,
          isActualPosition: true,
          segmentProgress: 0.4,
          speedKmh: 82.5,
          bearingDegrees: 270,
        ),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        const LiveStatusScreen(
          trainNumber: '12951',
          trainName: 'Test Rajdhani',
        ),
        repository,
      ),
    );
    await _settle(tester);

    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('12 min late'), findsOneWidget);
    expect(find.textContaining('BRC'), findsOneWidget);
    expect(find.textContaining('83 km/h'), findsOneWidget);
    expect(find.textContaining('Ratlam'), findsOneWidget);
    expect(find.textContaining('10:30'), findsOneWidget);
  });

  testWidgets('never shows a delay row when delayMinutes is null', (
    tester,
  ) async {
    final repository = _StubRepository(_status(delayMinutes: null));
    await tester.pumpWidget(
      _wrap(const LiveStatusScreen(trainNumber: '12951'), repository),
    );
    await _settle(tester);

    expect(find.textContaining('late'), findsNothing);
    expect(find.textContaining('On time'), findsNothing);
  });

  testWidgets('never shows a speed row when speedKmh is null', (tester) async {
    final repository = _StubRepository(
      _status(
        currentLocation: const LiveCurrentLocation(
          stationCode: 'BRC',
          sequence: 4,
          status: 'departed',
          isHalt: false,
          isActualPosition: true,
          segmentProgress: null,
          speedKmh: null,
          bearingDegrees: null,
        ),
      ),
    );
    await tester.pumpWidget(
      _wrap(const LiveStatusScreen(trainNumber: '12951'), repository),
    );
    await _settle(tester);

    expect(find.textContaining('km/h'), findsNothing);
  });

  testWidgets('shows the exact safe error message on failure, with Retry', (
    tester,
  ) async {
    final repository = _StubRepository(
      const LiveStatusException(
        LiveStatusFailureCategory.notFound,
        "Live status isn't available for this train.",
      ),
    );
    await tester.pumpWidget(
      _wrap(const LiveStatusScreen(trainNumber: '99999'), repository),
    );
    await _settle(tester);

    expect(
      find.text("Live status isn't available for this train."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    // Never a raw provider/backend name anywhere on screen.
    expect(find.textContaining('RailRadar'), findsNothing);
  });

  testWidgets('shows an exception banner for a diverted train', (tester) async {
    final repository = _StubRepository(
      _status(
        exceptions: const [
          LiveException(
            type: LiveExceptionType.diverted,
            message: 'Diverted via alternate route',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _wrap(const LiveStatusScreen(trainNumber: '12951'), repository),
    );
    await _settle(tester);

    expect(find.text('Diverted'), findsOneWidget);
    expect(find.text('Diverted via alternate route'), findsOneWidget);
  });

  testWidgets('the back button returns to the caller', (tester) async {
    final repository = _StubRepository(_status());
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LiveStatusScreen(trainNumber: '12951'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        repository,
      ),
    );

    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.byType(LiveStatusScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.byType(LiveStatusScreen), findsNothing);
  });
}
