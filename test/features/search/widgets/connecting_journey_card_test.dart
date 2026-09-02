import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/data/providers/running_days_lookup_providers.dart';
import 'package:train_yatri/domain/entities/connecting_journey.dart';
import 'package:train_yatri/domain/entities/direct_service.dart';
import 'package:train_yatri/domain/entities/railway_time.dart';
import 'package:train_yatri/domain/entities/route_stop.dart';
import 'package:train_yatri/domain/entities/station.dart';
import 'package:train_yatri/domain/entities/train_service.dart';
import 'package:train_yatri/domain/repositories/running_days_lookup_repository.dart';
import 'package:train_yatri/features/search/widgets/connecting_journey_card.dart';
import 'package:train_yatri/features/train_details/train_details_screen.dart';

import '../../../test_support/fake_railway_repository.dart';

const _jxn = Station(stationId: 2, code: 'JXN', name: 'Junction Gamma');

const _trainA = TrainService(
  trainId: 101,
  number: '11111',
  name: 'Leg A Express',
  isActive: true,
);
const _trainB = TrainService(
  trainId: 102,
  number: '22222',
  name: 'Leg B Express',
  isActive: true,
);

final _legA = DirectService(
  train: _trainA,
  fromStop: const RouteStop(
    routeStopId: 1,
    trainId: 101,
    stationId: 1,
    stopSequence: 1,
    dayOffset: 0,
    departureTime: RailwayTime(hour: 9, minute: 0),
  ),
  toStop: const RouteStop(
    routeStopId: 2,
    trainId: 101,
    stationId: 2,
    stopSequence: 2,
    dayOffset: 0,
    arrivalTime: RailwayTime(hour: 11, minute: 0),
  ),
);

final _legB = DirectService(
  train: _trainB,
  fromStop: const RouteStop(
    routeStopId: 3,
    trainId: 102,
    stationId: 2,
    stopSequence: 1,
    dayOffset: 0,
    departureTime: RailwayTime(hour: 12, minute: 0),
  ),
  toStop: const RouteStop(
    routeStopId: 4,
    trainId: 102,
    stationId: 3,
    stopSequence: 2,
    dayOffset: 0,
    arrivalTime: RailwayTime(hour: 15, minute: 0),
  ),
);

final _journey = ConnectingJourney(
  legA: _legA,
  interchange: _jxn,
  legB: _legB,
  waitingDuration: const Duration(hours: 1),
  totalDuration: const Duration(hours: 6),
);

class _NeverConfirmsRunningDays implements RunningDaysLookupRepository {
  @override
  Future<Map<String, RunningDaysAnswer>> getRunningDays(
    List<String> trainNumbers,
  ) async => {
    for (final number in trainNumbers)
      number: const RunningDaysAnswer(RunningDaysLookupStatus.pending),
  };
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      fakeRailwayRepositoryOverride(),
      runningDaysLookupRepositoryProvider.overrideWithValue(
        _NeverConfirmsRunningDays(),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('tapping leg A opens Train Details for leg A\'s train with the '
      'searched date', (tester) async {
    final searchedDate = DateTime(2027, 3, 15);
    await tester.pumpWidget(
      _wrap(ConnectingJourneyCard(journey: _journey, date: searchedDate)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leg A Express'));
    await tester.pumpAndSettle();

    final screen = tester.widget<TrainDetailsScreen>(
      find.byType(TrainDetailsScreen),
    );
    expect(screen.train.number, '11111');
    expect(screen.journeyDate, searchedDate);
  });

  testWidgets('tapping leg B opens Train Details for leg B\'s train with the '
      'same searched date', (tester) async {
    final searchedDate = DateTime(2027, 3, 15);
    await tester.pumpWidget(
      _wrap(ConnectingJourneyCard(journey: _journey, date: searchedDate)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leg B Express'));
    await tester.pumpAndSettle();

    final screen = tester.widget<TrainDetailsScreen>(
      find.byType(TrainDetailsScreen),
    );
    expect(screen.train.number, '22222');
    expect(screen.journeyDate, searchedDate);
  });
}
