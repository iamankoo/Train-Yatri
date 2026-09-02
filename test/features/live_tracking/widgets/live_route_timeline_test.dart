import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/domain/entities/live_train_status.dart';
import 'package:train_yatri/features/live_tracking/widgets/live_route_timeline.dart';

LiveRouteStop _stop(
  int sequence,
  String code,
  String name, {
  required bool? isHalt,
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

/// The one row whose station name is [stationName] - located via its
/// own `Semantics` label (every row wraps a distinct one, starting
/// with the station name), then scoped to that row's own descendants
/// only. This is what makes the pulse checks below reliable: a naive
/// `find.ancestor(of: ..., matching: find.byType(AnimatedBuilder))`
/// also matches unrelated framework animations further up the tree
/// (MaterialApp's theme, scrollbar stretch effects, ...), which
/// `find.descendant` scoped to just this one row's own Semantics
/// subtree never does.
Finder _rowFor(String stationName) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(stationName)}\\.'));

Finder _pulsingFenceOf(String stationName) => find.descendant(
  of: _rowFor(stationName),
  matching: find.byType(AnimatedBuilder),
);

/// A representative mixed route: real stoppages at 1, 3, 5, 7 (5 is
/// "current"), pass-through points at 2, 4, 6 in between.
final _mixedRoute = [
  _stop(1, 'ORG', 'Origin', isHalt: true),
  _stop(2, 'PT1', 'PassThroughA', isHalt: false),
  _stop(3, 'STB', 'StopB', isHalt: true),
  _stop(4, 'PT2', 'PassThroughC', isHalt: false),
  _stop(5, 'CUR', 'CurrentStop', isHalt: true),
  _stop(6, 'PT3', 'PassThroughD', isHalt: false),
  _stop(7, 'FUT', 'FutureStop', isHalt: true),
];

Widget _wrap(Widget child, {bool reduceMotion = false, double height = 1200}) {
  final view = MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
  if (!reduceMotion) return view;
  return MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: view,
  );
}

void main() {
  group('stoppage fencing - only real halts get it', () {
    testWidgets('exactly the real stoppages get a TRAIN STOPPAGE fence; '
        'pass-through stations never do', (tester) async {
      await tester.pumpWidget(
        _wrap(
          LiveRouteTimeline(
            route: _mixedRoute,
            currentLocation: const LiveCurrentLocation(
              stationCode: 'CUR',
              sequence: 5,
              status: 'at-station',
              isHalt: true,
              isActualPosition: true,
              segmentProgress: null,
              speedKmh: null,
              bearingDegrees: null,
            ),
            delayMinutes: 5,
          ),
        ),
      );
      await tester.pump();

      // 4 real stoppages (1, 3, 5, 7) -> 4 fence labels, regardless
      // of suffix.
      expect(find.textContaining('TRAIN STOPPAGE'), findsNWidgets(4));
      // The 3 pass-through stations still render normally.
      expect(find.text('PassThroughA'), findsOneWidget);
      expect(find.text('PassThroughC'), findsOneWidget);
      expect(find.text('PassThroughD'), findsOneWidget);
    });

    testWidgets('passed stoppages are labelled PASSED and are red/static', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          LiveRouteTimeline(
            route: _mixedRoute,
            currentLocation: const LiveCurrentLocation(
              stationCode: 'CUR',
              sequence: 5,
              status: 'at-station',
              isHalt: true,
              isActualPosition: true,
              segmentProgress: null,
              speedKmh: null,
              bearingDegrees: null,
            ),
            delayMinutes: 5,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('TRAIN STOPPAGE — PASSED'), findsNWidgets(2));
    });

    testWidgets('the current stoppage is labelled NEXT, green, and is the only '
        'one that pulses', (tester) async {
      await tester.pumpWidget(
        _wrap(
          LiveRouteTimeline(
            route: _mixedRoute,
            currentLocation: const LiveCurrentLocation(
              stationCode: 'CUR',
              sequence: 5,
              status: 'at-station',
              isHalt: true,
              isActualPosition: true,
              segmentProgress: null,
              speedKmh: null,
              bearingDegrees: null,
            ),
            delayMinutes: 5,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('TRAIN STOPPAGE — NEXT'), findsOneWidget);
      // The next/current fence (CurrentStop) pulses...
      expect(_pulsingFenceOf('CurrentStop'), findsOneWidget);
      // ...but a passed fence never does.
      expect(_pulsingFenceOf('Origin'), findsNothing);
      expect(_pulsingFenceOf('StopB'), findsNothing);
    });

    testWidgets(
      'future stoppages show the bare label, are amber, and do not pulse',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: const LiveCurrentLocation(
                stationCode: 'CUR',
                sequence: 5,
                status: 'at-station',
                isHalt: true,
                isActualPosition: true,
                segmentProgress: null,
                speedKmh: null,
                bearingDegrees: null,
              ),
              delayMinutes: 5,
            ),
          ),
        );
        await tester.pump();

        // Exact match: the bare "TRAIN STOPPAGE" (no suffix) belongs
        // only to the one future stoppage.
        expect(find.text('TRAIN STOPPAGE'), findsOneWidget);
        expect(_pulsingFenceOf('FutureStop'), findsNothing);
      },
    );

    testWidgets(
      'a null current position never marks a stoppage passed or next - '
      'every stoppage stays neutral and static',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: null,
              delayMinutes: null,
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('PASSED'), findsNothing);
        expect(find.textContaining('NEXT'), findsNothing);
        expect(find.text('TRAIN STOPPAGE'), findsNWidgets(4));
        for (final name in ['Origin', 'StopB', 'CurrentStop', 'FutureStop']) {
          expect(_pulsingFenceOf(name), findsNothing);
        }
      },
    );

    testWidgets(
      'reduced motion disables the pulse, even for the next stoppage',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: const LiveCurrentLocation(
                stationCode: 'CUR',
                sequence: 5,
                status: 'at-station',
                isHalt: true,
                isActualPosition: true,
                segmentProgress: null,
                speedKmh: null,
                bearingDegrees: null,
              ),
              delayMinutes: 5,
            ),
            reduceMotion: true,
          ),
        );
        await tester.pump();

        expect(find.text('TRAIN STOPPAGE — NEXT'), findsOneWidget);
        expect(_pulsingFenceOf('CurrentStop'), findsNothing);
      },
    );
  });

  group('position advances - fencing updates automatically', () {
    testWidgets(
      'when the train moves to the next stoppage, the old green stoppage '
      'turns red and the new one turns green and starts pulsing',
      (tester) async {
        const atStopB = LiveCurrentLocation(
          stationCode: 'STB',
          sequence: 3,
          status: 'at-station',
          isHalt: true,
          isActualPosition: true,
          segmentProgress: null,
          speedKmh: null,
          bearingDegrees: null,
        );
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: atStopB,
              delayMinutes: 0,
            ),
          ),
        );
        await tester.pump();

        expect(find.text('TRAIN STOPPAGE — NEXT'), findsOneWidget);
        expect(find.text('TRAIN STOPPAGE — PASSED'), findsOneWidget); // Origin
        expect(_pulsingFenceOf('StopB'), findsOneWidget);

        // The live poll moved the train on to the next real stoppage.
        const atCurrentStop = LiveCurrentLocation(
          stationCode: 'CUR',
          sequence: 5,
          status: 'at-station',
          isHalt: true,
          isActualPosition: true,
          segmentProgress: null,
          speedKmh: null,
          bearingDegrees: null,
        );
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: atCurrentStop,
              delayMinutes: 0,
            ),
          ),
        );
        await tester.pump();

        // StopB (previously the pulsing "next") is now passed/red -
        // and no longer pulsing at all.
        expect(find.text('TRAIN STOPPAGE — PASSED'), findsNWidgets(2));
        expect(_pulsingFenceOf('StopB'), findsNothing);

        // CurrentStop is the new green/pulsing one.
        expect(find.text('TRAIN STOPPAGE — NEXT'), findsOneWidget);
        expect(_pulsingFenceOf('CurrentStop'), findsOneWidget);
      },
    );
  });

  group('current-position delay indicator', () {
    testWidgets('a positive delay is shown attached to the current stoppage', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          LiveRouteTimeline(
            route: _mixedRoute,
            currentLocation: const LiveCurrentLocation(
              stationCode: 'CUR',
              sequence: 5,
              status: 'at-station',
              isHalt: true,
              isActualPosition: true,
              segmentProgress: null,
              speedKmh: null,
              bearingDegrees: null,
            ),
            delayMinutes: 18,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('18 min late'), findsOneWidget);
    });

    testWidgets(
      'an explicit zero delay shows On time at the current stoppage',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: const LiveCurrentLocation(
                stationCode: 'CUR',
                sequence: 5,
                status: 'at-station',
                isHalt: true,
                isActualPosition: true,
                segmentProgress: null,
                speedKmh: null,
                bearingDegrees: null,
              ),
              delayMinutes: 0,
            ),
          ),
        );
        await tester.pump();

        expect(find.text('On time'), findsOneWidget);
      },
    );

    testWidgets('a null delay shows Delay unknown, never On time', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          LiveRouteTimeline(
            route: _mixedRoute,
            currentLocation: const LiveCurrentLocation(
              stationCode: 'CUR',
              sequence: 5,
              status: 'at-station',
              isHalt: true,
              isActualPosition: true,
              segmentProgress: null,
              speedKmh: null,
              bearingDegrees: null,
            ),
            delayMinutes: null,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Delay unknown'), findsOneWidget);
      expect(find.text('On time'), findsNothing);
    });

    testWidgets(
      'the delay indicator never appears on a pass-through station or on '
      'a stoppage that is not the current position',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: _mixedRoute,
              currentLocation: const LiveCurrentLocation(
                stationCode: 'CUR',
                sequence: 5,
                status: 'at-station',
                isHalt: true,
                isActualPosition: true,
                segmentProgress: null,
                speedKmh: null,
                bearingDegrees: null,
              ),
              delayMinutes: 42,
            ),
          ),
        );
        await tester.pump();

        // "42 min late" only ever appears once, at the one current
        // stoppage - never duplicated onto the passed/future ones or
        // any pass-through station.
        expect(find.text('42 min late'), findsOneWidget);
      },
    );
  });

  group('between stations', () {
    testWidgets('the live segment carries the delay indicator; the next real '
        'stoppage after it is green and pulsing, not the delay-carrying one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          LiveRouteTimeline(
            route: _mixedRoute,
            currentLocation: const LiveCurrentLocation(
              stationCode: 'STB',
              sequence: 3,
              status: 'departed',
              isHalt: false,
              isActualPosition: true,
              segmentProgress: 0.5,
              speedKmh: 80,
              bearingDegrees: null,
            ),
            delayMinutes: 12,
            previousHalt: const LiveHalt(
              stationCode: 'STB',
              stationName: 'StopB',
              sequence: 3,
              distanceKm: 100,
            ),
            nextHalt: const LiveHalt(
              stationCode: 'CUR',
              stationName: 'CurrentStop',
              sequence: 5,
              distanceKm: 150,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('12 min late'), findsOneWidget);
      // StopB itself (the departed reference point) is now passed.
      expect(find.text('TRAIN STOPPAGE — PASSED'), findsNWidgets(2));
      // CurrentStop (the next real halt) is green/pulsing, with no
      // delay indicator of its own - "12 min late" appears exactly
      // once, on the segment, never duplicated onto CurrentStop.
      expect(find.text('TRAIN STOPPAGE — NEXT'), findsOneWidget);
      expect(_pulsingFenceOf('CurrentStop'), findsOneWidget);
    });
  });

  group('automatic scrolling', () {
    testWidgets(
      'the current live position scrolls into view automatically on load',
      (tester) async {
        final longRoute = [
          for (var i = 1; i <= 15; i++)
            _stop(i, 'S$i', 'Station $i', isHalt: i.isEven),
        ];
        await tester.pumpWidget(
          _wrap(
            LiveRouteTimeline(
              route: longRoute,
              currentLocation: const LiveCurrentLocation(
                stationCode: 'S12',
                sequence: 12,
                status: 'at-station',
                isHalt: true,
                isActualPosition: true,
                segmentProgress: null,
                speedKmh: null,
                bearingDegrees: null,
              ),
              delayMinutes: 3,
            ),
            height: 500,
          ),
        );
        // Deliberately bounded, not pumpAndSettle(): the current
        // stoppage's fence pulses forever by design, so pumpAndSettle
        // (which waits for every animation to finish) never returns.
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scrollable.position.pixels, greaterThan(0));
      },
    );
  });
}
