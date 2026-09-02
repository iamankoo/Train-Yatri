import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/data/providers/running_days_lookup_providers.dart';
import 'package:train_yatri/domain/entities/live_train_status.dart';
import 'package:train_yatri/domain/entities/train_service.dart';
import 'package:train_yatri/domain/repositories/live_status_repository.dart';
import 'package:train_yatri/domain/repositories/running_days_lookup_repository.dart';
import 'package:train_yatri/features/live_tracking/live_status_controller.dart';
import 'package:train_yatri/features/train_details/train_details_screen.dart';
import 'package:train_yatri/shared/theme/app_colors.dart';

import '../../test_support/fake_railway_repository.dart';

/// A journey date whose weekday is computed rather than assumed, so
/// tests are correct regardless of which day the referenced calendar
/// date actually falls on.
final _journeyDate = DateTime(2026, 9, 2);

const _dayKeys = {
  DateTime.monday: 'monday',
  DateTime.tuesday: 'tuesday',
  DateTime.wednesday: 'wednesday',
  DateTime.thursday: 'thursday',
  DateTime.friday: 'friday',
  DateTime.saturday: 'saturday',
  DateTime.sunday: 'sunday',
};

Map<String, bool> _daysMap(bool Function(int weekday) predicate) => {
  for (final entry in _dayKeys.entries) entry.value: predicate(entry.key),
};

class _FakeRunningDaysLookupRepository implements RunningDaysLookupRepository {
  _FakeRunningDaysLookupRepository(this.answers);

  final Map<String, RunningDaysAnswer> answers;
  List<String>? lastRequested;

  @override
  Future<Map<String, RunningDaysAnswer>> getRunningDays(
    List<String> trainNumbers,
  ) async {
    lastRequested = trainNumbers;
    return answers;
  }
}

class _FakeLiveStatusRepository implements LiveStatusRepository {
  _FakeLiveStatusRepository(this._result);

  final Object _result; // LiveTrainStatus or LiveStatusException
  int callCount = 0;
  String? lastTrainNumber;
  String? lastJourneyDate;

  @override
  Future<LiveTrainStatus> getLiveStatus(
    String trainNumber, {
    String? journeyDate,
  }) async {
    callCount++;
    lastTrainNumber = trainNumber;
    lastJourneyDate = journeyDate;
    final result = _result;
    if (result is LiveStatusException) throw result;
    return result as LiveTrainStatus;
  }
}

LiveTrainStatus _liveStatus({
  int? delayMinutes,
  LiveStatusCategory status = LiveStatusCategory.running,
  LiveCurrentLocation? currentLocation,
  List<LiveRouteStop> route = const [],
  LiveHalt? previousHalt,
  LiveHalt? nextHalt,
  List<LiveException> exceptions = const [],
}) => LiveTrainStatus(
  trainNumber: '00101T',
  trainName: 'Test Overnight Express',
  journeyDate: '2026-09-02',
  status: status,
  delayMinutes: delayMinutes,
  lastUpdatedAt: DateTime(2026, 9, 2, 10, 0),
  isLive: true,
  currentLocation: currentLocation,
  previousHalt: previousHalt,
  nextHalt: nextHalt,
  route: route,
  exceptions: exceptions,
);

LiveRouteStop _stop(
  int sequence,
  String code,
  String name, {
  bool? isHalt = true,
}) => LiveRouteStop(
  sequence: sequence,
  stationCode: code,
  stationName: name,
  isHalt: isHalt,
  scheduledArrival: null,
  scheduledDeparture: null,
  actualArrival: null,
  actualDeparture: null,
  arrivalDelayMinutes: null,
  departureDelayMinutes: null,
  status: null,
  distanceKm: null,
  platform: null,
);

Widget _wrap(
  Widget child, {
  required RunningDaysLookupRepository runningDays,
  required LiveStatusRepository liveStatus,
}) {
  return ProviderScope(
    overrides: [
      fakeRailwayRepositoryOverride(),
      runningDaysLookupRepositoryProvider.overrideWithValue(runningDays),
      liveStatusRepositoryProvider.overrideWithValue(liveStatus),
    ],
    child: MaterialApp(home: child),
  );
}

/// A bounded stand-in for `pumpAndSettle()`: the live delay/segment
/// indicators pulse forever by design (Block 6 UI fix, Part 5), so
/// `pumpAndSettle` - which waits for every animation to finish - never
/// returns while one is on screen. This instead pumps enough frames to
/// flush the real async chain (running-days lookup -> live status
/// fetch -> auto-scroll post-frame callback) and any page-route
/// transition, without waiting on an animation that never stops.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _useTallSurface(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TrainService> _lookupTrain(String number) async {
  final repository = await buildFakeRailwayRepository();
  return (await repository.getTrainByNumber(number))!;
}

_FakeRunningDaysLookupRepository _confirmedRunning() =>
    _FakeRunningDaysLookupRepository({
      '00101T': RunningDaysAnswer(
        RunningDaysLookupStatus.confirmed,
        days: _daysMap((w) => w == _journeyDate.weekday),
      ),
    });

_FakeRunningDaysLookupRepository _confirmedNotRunning() =>
    _FakeRunningDaysLookupRepository({
      '00101T': RunningDaysAnswer(
        RunningDaysLookupStatus.confirmed,
        days: _daysMap((w) => w != _journeyDate.weekday),
      ),
    });

_FakeRunningDaysLookupRepository _unknownRunning() =>
    _FakeRunningDaysLookupRepository({
      '00101T': const RunningDaysAnswer(RunningDaysLookupStatus.pending),
    });

_FakeLiveStatusRepository _neverCalledLiveStatus() => _FakeLiveStatusRepository(
  const LiveStatusException(
    LiveStatusFailureCategory.unknown,
    'should not be called',
  ),
);

void main() {
  testWidgets('shows the train name and number', (tester) async {
    final train = await _lookupTrain('00101T');
    await tester.pumpWidget(
      _wrap(
        TrainDetailsScreen(train: train, journeyDate: _journeyDate),
        runningDays: _unknownRunning(),
        liveStatus: _neverCalledLiveStatus(),
      ),
    );
    await _settle(tester);

    expect(find.text('Test Overnight Express'), findsOneWidget);
    expect(find.textContaining('#00101T'), findsOneWidget);
  });

  testWidgets(
    'renders the real ordered route: origin, intermediate stop, destination',
    (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _unknownRunning(),
          liveStatus: _neverCalledLiveStatus(),
        ),
      );
      await _settle(tester);

      expect(find.textContaining('New Delta Alpha'), findsOneWidget);
      expect(find.textContaining('Junction Gamma'), findsOneWidget);
      expect(find.textContaining('Mumbai Central Beta'), findsOneWidget);
    },
  );

  testWidgets('marks the overnight stop with a +1d badge (day_offset, not '
      'raw clock time)', (tester) async {
    final train = await _lookupTrain('00101T');
    await tester.pumpWidget(
      _wrap(
        TrainDetailsScreen(train: train, journeyDate: _journeyDate),
        runningDays: _unknownRunning(),
        liveStatus: _neverCalledLiveStatus(),
      ),
    );
    await _settle(tester);

    expect(find.text('+1d'), findsOneWidget);
  });

  testWidgets('a same-day train shows no day-offset badge at all', (
    tester,
  ) async {
    final train = await _lookupTrain('00102T');
    await tester.pumpWidget(
      _wrap(
        TrainDetailsScreen(train: train, journeyDate: _journeyDate),
        runningDays: _unknownRunning(),
        liveStatus: _neverCalledLiveStatus(),
      ),
    );
    await _settle(tester);

    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets(
    'never shows fabricated live fields inline in the static-only route',
    (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _unknownRunning(),
          liveStatus: _neverCalledLiveStatus(),
        ),
      );
      await _settle(tester);

      for (final forbidden in [
        'Platform',
        'PNR',
        'ETA',
        'Fare',
        'Seat',
        'km/h',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    },
  );

  group('automatic Live Status (Block 6 UI fix)', () {
    testWidgets('confirmed running on the selected date: Live Status appears '
        'automatically, no button required', (tester) async {
      final train = await _lookupTrain('00101T');
      final liveStatus = _FakeLiveStatusRepository(
        _liveStatus(
          delayMinutes: 12,
          currentLocation: const LiveCurrentLocation(
            stationCode: 'JXN',
            sequence: 2,
            status: 'at-station',
            isHalt: true,
            isActualPosition: true,
            segmentProgress: null,
            speedKmh: null,
            bearingDegrees: null,
          ),
          route: [
            _stop(1, 'NDA', 'New Delta Alpha'),
            _stop(2, 'JXN', 'Junction Gamma'),
            _stop(3, 'MCB', 'Mumbai Central Beta'),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: liveStatus,
        ),
      );
      await _settle(tester);

      expect(find.text('RUNNING'), findsOneWidget);
      // Shown twice by design: once in the top header, once attached
      // to the current live position in the route timeline - the
      // same real delayMinutes, never a second calculation.
      expect(find.text('12 min late'), findsNWidgets(2));
      expect(liveStatus.callCount, 1);
    });

    testWidgets('passes the exact searched journey date, never today\'s date', (
      tester,
    ) async {
      final train = await _lookupTrain('00101T');
      final liveStatus = _FakeLiveStatusRepository(_liveStatus());
      final farFutureDate = DateTime(2027, 3, 15);

      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: farFutureDate),
          runningDays: _FakeRunningDaysLookupRepository({
            '00101T': RunningDaysAnswer(
              RunningDaysLookupStatus.confirmed,
              days: _daysMap((w) => w == farFutureDate.weekday),
            ),
          }),
          liveStatus: liveStatus,
        ),
      );
      await _settle(tester);

      expect(liveStatus.lastTrainNumber, '00101T');
      expect(liveStatus.lastJourneyDate, '2027-03-15');
    });

    testWidgets('confirmed NOT running on the selected date: no live section, '
        'no live request, static route still shown', (tester) async {
      final train = await _lookupTrain('00101T');
      final liveStatus = _neverCalledLiveStatus();

      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedNotRunning(),
          liveStatus: liveStatus,
        ),
      );
      await _settle(tester);

      expect(find.text('Not running on the selected date'), findsOneWidget);
      expect(find.textContaining('New Delta Alpha'), findsOneWidget);
      expect(liveStatus.callCount, 0);
    });

    testWidgets(
      'unknown running-day data: never assumes running, offers a manual '
      'check instead, which then fetches real data on demand',
      (tester) async {
        final train = await _lookupTrain('00101T');
        final liveStatus = _FakeLiveStatusRepository(_liveStatus());

        await tester.pumpWidget(
          _wrap(
            TrainDetailsScreen(train: train, journeyDate: _journeyDate),
            runningDays: _unknownRunning(),
            liveStatus: liveStatus,
          ),
        );
        await _settle(tester);

        expect(liveStatus.callCount, 0);
        expect(find.text('Check now'), findsOneWidget);

        await tester.tap(find.text('Check now'));
        await _settle(tester);

        expect(liveStatus.callCount, 1);
        expect(find.text('RUNNING'), findsOneWidget);
      },
    );

    testWidgets('live status unavailable: static route stays visible with an '
        'inline retry, page never blocked or crashed', (tester) async {
      final train = await _lookupTrain('00101T');
      final liveStatus = _FakeLiveStatusRepository(
        const LiveStatusException(
          LiveStatusFailureCategory.notFound,
          "Live status isn't available for this train.",
        ),
      );

      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: liveStatus,
        ),
      );
      await _settle(tester);

      expect(
        find.text("Live status isn't available for this train."),
        findsOneWidget,
      );
      expect(find.textContaining('New Delta Alpha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explicit zero delay shows On time', (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: _FakeLiveStatusRepository(_liveStatus(delayMinutes: 0)),
        ),
      );
      await _settle(tester);

      expect(find.text('On time'), findsOneWidget);
    });

    testWidgets('null delay never shows On time', (tester) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: _FakeLiveStatusRepository(
            _liveStatus(delayMinutes: null),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('On time'), findsNothing);
      expect(find.text('Delay unknown'), findsOneWidget);
    });

    testWidgets('a positive delay renders with the error (red) color', (
      tester,
    ) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: _FakeLiveStatusRepository(_liveStatus(delayMinutes: 25)),
        ),
      );
      await _settle(tester);

      final text = tester.widget<Text>(find.text('25 min late'));
      expect(text.style?.color, AppColors.error);
    });

    testWidgets(
      'a train between two stations shows a live segment, not a single '
      'station falsely marked current',
      (tester) async {
        final train = await _lookupTrain('00101T');
        await tester.pumpWidget(
          _wrap(
            TrainDetailsScreen(train: train, journeyDate: _journeyDate),
            runningDays: _confirmedRunning(),
            liveStatus: _FakeLiveStatusRepository(
              _liveStatus(
                currentLocation: const LiveCurrentLocation(
                  stationCode: 'NDA',
                  sequence: 1,
                  status: 'departed',
                  isHalt: false,
                  isActualPosition: true,
                  segmentProgress: 0.5,
                  speedKmh: 80,
                  bearingDegrees: null,
                ),
                previousHalt: const LiveHalt(
                  stationCode: 'NDA',
                  stationName: 'New Delta Alpha',
                  sequence: 1,
                  distanceKm: 0,
                ),
                nextHalt: const LiveHalt(
                  stationCode: 'JXN',
                  stationName: 'Junction Gamma',
                  sequence: 2,
                  distanceKm: 50,
                ),
                route: [
                  _stop(1, 'NDA', 'New Delta Alpha'),
                  _stop(2, 'JXN', 'Junction Gamma'),
                  _stop(3, 'MCB', 'Mumbai Central Beta'),
                ],
              ),
            ),
          ),
        );
        await _settle(tester);

        expect(find.text('LIVE'), findsOneWidget);
        expect(find.textContaining('New Delta Alpha'), findsWidgets);
        expect(find.textContaining('Junction Gamma'), findsWidgets);
      },
    );

    testWidgets(
      'the route auto-scrolls toward the current position without manual '
      'scrolling',
      (tester) async {
        final train = await _lookupTrain('00101T');
        final longRoute = [
          for (var i = 1; i <= 12; i++) _stop(i, 'S$i', 'Station $i'),
        ];

        await tester.pumpWidget(
          _wrap(
            TrainDetailsScreen(train: train, journeyDate: _journeyDate),
            runningDays: _confirmedRunning(),
            liveStatus: _FakeLiveStatusRepository(
              _liveStatus(
                currentLocation: const LiveCurrentLocation(
                  stationCode: 'S9',
                  sequence: 9,
                  status: 'at-station',
                  isHalt: true,
                  isActualPosition: true,
                  segmentProgress: null,
                  speedKmh: null,
                  bearingDegrees: null,
                ),
                route: longRoute,
              ),
            ),
          ),
        );
        await _settle(tester);

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scrollable.position.pixels, greaterThan(0));
      },
    );

    testWidgets('a cancelled train renders its status without crashing', (
      tester,
    ) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: _FakeLiveStatusRepository(
            _liveStatus(status: LiveStatusCategory.cancelled),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('CANCELLED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a diverted train shows the exception banner, not raw JSON', (
      tester,
    ) async {
      final train = await _lookupTrain('00101T');
      await tester.pumpWidget(
        _wrap(
          TrainDetailsScreen(train: train, journeyDate: _journeyDate),
          runningDays: _confirmedRunning(),
          liveStatus: _FakeLiveStatusRepository(
            _liveStatus(
              exceptions: const [
                LiveException(
                  type: LiveExceptionType.diverted,
                  message: 'Diverted via alternate route',
                ),
              ],
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Diverted'), findsOneWidget);
      expect(find.text('Diverted via alternate route'), findsOneWidget);
    });
  });

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
                    builder: (_) => TrainDetailsScreen(
                      train: train,
                      journeyDate: _journeyDate,
                    ),
                  ),
                ),
                child: const Text('open details'),
              ),
            ),
          ),
        ),
        runningDays: _unknownRunning(),
        liveStatus: _neverCalledLiveStatus(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('open details'));
    await _settle(tester);
    expect(find.byType(TrainDetailsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.byType(TrainDetailsScreen), findsNothing);
    expect(find.text('open details'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets(
      'lays out without horizontal overflow at ${width}dp width (static)',
      (tester) async {
        _useTallSurface(tester, width: width);
        final train = await _lookupTrain('00101T');
        await tester.pumpWidget(
          _wrap(
            TrainDetailsScreen(train: train, journeyDate: _journeyDate),
            runningDays: _unknownRunning(),
            liveStatus: _neverCalledLiveStatus(),
          ),
        );
        await _settle(tester);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'lays out without horizontal overflow at ${width}dp width (live)',
      (tester) async {
        _useTallSurface(tester, width: width);
        final train = await _lookupTrain('00101T');
        await tester.pumpWidget(
          _wrap(
            TrainDetailsScreen(train: train, journeyDate: _journeyDate),
            runningDays: _confirmedRunning(),
            liveStatus: _FakeLiveStatusRepository(
              _liveStatus(
                delayMinutes: 18,
                currentLocation: const LiveCurrentLocation(
                  stationCode: 'JXN',
                  sequence: 2,
                  status: 'at-station',
                  isHalt: true,
                  isActualPosition: true,
                  segmentProgress: null,
                  speedKmh: null,
                  bearingDegrees: null,
                ),
                route: [
                  _stop(1, 'NDA', 'New Delta Alpha'),
                  _stop(2, 'JXN', 'Junction Gamma'),
                  _stop(3, 'MCB', 'Mumbai Central Beta'),
                ],
              ),
            ),
          ),
        );
        await _settle(tester);

        expect(tester.takeException(), isNull);
      },
    );
  }
}
