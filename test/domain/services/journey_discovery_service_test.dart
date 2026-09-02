// Deterministic synthetic routing fixtures (Block 5, "Required
// connection tests"/"Routing edge cases") - not real stations/trains.
// Each scenario below uses its own disjoint set of station codes so
// scenarios never interact with each other in the same shared
// in-memory database.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/core/journey/journey_discovery_config.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/services/journey_discovery_service.dart';

import '../../data/test_support/ffi_setup.dart';

// --- Scenario 1: valid connection + insufficient buffer + already-left,
// all sharing one FROM/interchange/TO and one first-leg train, so each
// rejection reason can be isolated to one specific second-leg train.
const _stationsCsv = '''
code,name,city,state,latitude,longitude
S1A,Scenario1 Origin,,,,
S1J,Scenario1 Interchange,,,,
S1B,Scenario1 Destination,,,,
S2A,Scenario2 Origin,,,,
S2J,Scenario2 Interchange,,,,
S2B,Scenario2 Destination,,,,
S3A,Scenario3 Origin,,,,
S3J,Scenario3 Interchange,,,,
S3B,Scenario3 Destination,,,,
S4A,Scenario4 Origin,,,,
S4B,Scenario4 Destination,,,,
S5A,Scenario5 Origin,,,,
S5J,Scenario5 Interchange,,,,
S5B,Scenario5 Destination,,,,
S5C,Scenario5 Wrong Destination,,,,
S6A,Scenario6 Origin,,,,
S6J,Scenario6 Interchange,,,,
S6B,Scenario6 Destination,,,,
''';

const _trainsCsv = '''
number,name,is_active
91001T,S1 Leg A,1
91002T,S1 Leg B Valid,1
91003T,S1 Leg B Too Tight,1
91004T,S1 Leg B Already Left,1
92001T,S2 Night Leg A,1
92002T,S2 Night Leg B,1
93001T,S3 Direct Through,1
95001T,S5 Leg A,1
95002T,S5 Leg B Wrong Destination,1
96001T,S6 Leg A Fast,1
96002T,S6 Leg A Slow,1
96003T,S6 Leg B,1
''';

const _routeStopsCsv = '''
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
91001T,1,S1A,,08:00,0,0
91001T,2,S1J,10:00,,0,100
91002T,1,S1J,,10:40,0,0
91002T,2,S1B,12:00,,0,60
91003T,1,S1J,,10:15,0,0
91003T,2,S1B,11:15,,0,60
91004T,1,S1J,,09:30,0,0
91004T,2,S1B,10:45,,0,60
92001T,1,S2A,,23:00,0,0
92001T,2,S2J,00:30,,1,150
92002T,1,S2J,,01:15,0,0
92002T,2,S2B,05:00,,0,200
93001T,1,S3A,,07:00,0,0
93001T,2,S3J,09:00,09:10,0,120
93001T,3,S3B,10:30,,0,180
95001T,1,S5A,,08:00,0,0
95001T,2,S5J,09:00,,0,90
95002T,1,S5J,,09:30,0,0
95002T,2,S5C,10:00,,0,30
96001T,1,S6A,,06:00,0,0
96001T,2,S6J,07:00,,0,80
96002T,1,S6A,,05:00,0,0
96002T,2,S6J,08:00,,0,80
96003T,1,S6J,,08:30,0,0
96003T,2,S6B,09:30,,0,50
''';

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  late Database db;
  late SqliteRailwayRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await configureRailwayConnection(db);
    for (final statement in schema.schemaStatements) {
      await db.execute(statement);
    }
    await RailwayImporter(db).import(
      stations: parseCsvSource(_stationsCsv),
      trains: parseCsvSource(_trainsCsv),
      routeStops: parseCsvSource(_routeStopsCsv),
      runningDays: const [],
      datasetSource: 'synthetic journey-discovery fixture',
      datasetVersion: 'test-1',
    );
    repository = SqliteRailwayRepository(db);
  });

  tearDown(() => db.close());

  Future<int> stationId(String code) async =>
      (await repository.getStationByCode(code))!.stationId;

  test(
    'scenario 1: finds exactly the one valid connection, correctly '
    'rejecting insufficient buffer and already-departed candidates',
    () async {
      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: await stationId('S1A'),
        toStationId: await stationId('S1B'),
      );

      expect(result.direct, isEmpty);
      expect(result.connecting, hasLength(1));

      final connection = result.connecting.single;
      expect(connection.legA.train.number, '91001T');
      expect(connection.legB.train.number, '91002T');
      expect(connection.interchange.code, 'S1J');
      expect(connection.waitingDuration, const Duration(minutes: 40));
      expect(connection.totalDuration, const Duration(hours: 4));
    },
  );

  test('scenario 2: a valid overnight connection is found, with correct '
      'day_offset-aware waiting/total duration across two different '
      "trains' own day_offset numbering", () async {
    final result = await JourneyDiscoveryService.discover(
      repository: repository,
      fromStationId: await stationId('S2A'),
      toStationId: await stationId('S2B'),
    );

    expect(result.connecting, hasLength(1));
    final connection = result.connecting.single;
    expect(connection.legA.train.number, '92001T');
    expect(connection.legB.train.number, '92002T');
    expect(connection.waitingDuration, const Duration(minutes: 45));
    expect(connection.totalDuration, const Duration(hours: 6));
  });

  test(
    'scenario 3: a train that already reaches the destination directly '
    '(and also happens to pass through a would-be interchange) is '
    'never offered as a connection to itself (same-train rejection)',
    () async {
      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: await stationId('S3A'),
        toStationId: await stationId('S3B'),
      );

      expect(result.direct, hasLength(1));
      expect(result.direct.single.train.number, '93001T');
      expect(result.connecting, isEmpty);
    },
  );

  test('scenario 4: no journey at all - neither direct nor connecting - '
      'produces two honestly empty lists, never a fabricated result', () async {
    final result = await JourneyDiscoveryService.discover(
      repository: repository,
      fromStationId: await stationId('S4A'),
      toStationId: await stationId('S4B'),
    );

    expect(result.direct, isEmpty);
    expect(result.connecting, isEmpty);
    expect(result.isEmpty, isTrue);
  });

  test('scenario 5: a second-leg candidate that never actually reaches TO '
      '(it goes to a different station from the interchange) does not '
      'produce a connection - destination route-order validation', () async {
    final result = await JourneyDiscoveryService.discover(
      repository: repository,
      fromStationId: await stationId('S5A'),
      toStationId: await stationId('S5B'),
    );

    expect(result.direct, isEmpty);
    expect(result.connecting, isEmpty);
  });

  test('scenario 6: ranking - a later, faster first leg with less overall '
      'wait ranks before an earlier, slower one with a longer wait, since '
      'both reach the same interchange/second leg', () async {
    final result = await JourneyDiscoveryService.discover(
      repository: repository,
      fromStationId: await stationId('S6A'),
      toStationId: await stationId('S6B'),
    );

    // 96001T (fast, dep 06:00, arr S6J 07:00) and 96002T (slow, dep
    // 05:00, arr S6J 08:00) both connect to 96003T (dep S6J 08:30).
    // 96001T waits 90 min (07:00 -> 08:30); 96002T waits 30 min
    // (08:00 -> 08:30) but departed FROM earlier. Both arrive S6B at
    // the same absolute clock time (09:30) - the earlier-departing
    // 96002T should therefore NOT be preferred by total-duration
    // alone; total duration for 96001T is 3h30m (06:00->09:30) and
    // for 96002T is 4h30m (05:00->09:30), so 96001T (shorter total
    // duration) ranks first.
    expect(result.connecting, hasLength(2));
    expect(result.connecting.first.legA.train.number, '96001T');
    expect(
      result.connecting.first.totalDuration,
      const Duration(hours: 3, minutes: 30),
    );
    expect(result.connecting.last.legA.train.number, '96002T');
    expect(
      result.connecting.last.totalDuration,
      const Duration(hours: 4, minutes: 30),
    );
  });

  group('bounded search (limits, Block 5 "Connection limits")', () {
    test('maxConnectingResults truncates even when more valid '
        'connections exist', () async {
      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: await stationId('S6A'),
        toStationId: await stationId('S6B'),
        config: const JourneyDiscoveryConfig(maxConnectingResults: 1),
      );
      expect(result.connecting, hasLength(1));
    });

    test(
      'maxFirstLegCandidates=0-equivalent (1, the minimum) still '
      'finds a connection when the earliest departure alone suffices',
      () async {
        final result = await JourneyDiscoveryService.discover(
          repository: repository,
          fromStationId: await stationId('S1A'),
          toStationId: await stationId('S1B'),
          config: const JourneyDiscoveryConfig(maxFirstLegCandidates: 1),
        );
        expect(result.connecting, hasLength(1));
      },
    );

    test('a stricter minimum connection buffer rejects a connection the '
        'default buffer would accept', () async {
      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: await stationId('S1A'),
        toStationId: await stationId('S1B'),
        config: const JourneyDiscoveryConfig(
          minimumConnectionBufferMinutes: 41,
        ),
      );
      // The only valid candidate (91002T) has exactly a 40-minute
      // gap - a 41-minute requirement must reject it too.
      expect(result.connecting, isEmpty);
    });
  });
}
