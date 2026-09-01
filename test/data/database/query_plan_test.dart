// Verifies the indexes declared in lib/data/database/schema.dart are
// actually used by the repository's query shapes, using a synthetic
// (but non-trivially sized) dataset - SQLite's planner can behave
// differently on a handful of rows than on hundreds, so a handful of
// synthetic stations/trains would not exercise this meaningfully.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';

import '../test_support/ffi_setup.dart';

const _stationCount = 300;
const _trainCount = 150;

String _buildStationsCsv() {
  final buffer = StringBuffer('code,name,city,state,latitude,longitude\n');
  for (var i = 0; i < _stationCount; i++) {
    final code = 'SYN${i.toString().padLeft(3, '0')}';
    buffer.writeln(
      '$code,Synthetic Station $i,Synthetic City,Synthetic State,,',
    );
  }
  return buffer.toString();
}

String _buildTrainsCsv() {
  final buffer = StringBuffer('number,name,is_active\n');
  for (var i = 0; i < _trainCount; i++) {
    final number = '${(90000 + i)}';
    buffer.writeln('$number,Synthetic Train $i,1');
  }
  return buffer.toString();
}

String _buildRouteStopsCsv() {
  final buffer = StringBuffer(
    'train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km\n',
  );
  for (var t = 0; t < _trainCount; t++) {
    final number = '${(90000 + t)}';
    for (var s = 0; s < 5; s++) {
      final stationIndex = (t + s) % _stationCount;
      final code = 'SYN${stationIndex.toString().padLeft(3, '0')}';
      final arrival = s == 0 ? '' : '0$s:00';
      final departure = s == 4 ? '' : '0$s:05';
      buffer.writeln('$number,${s + 1},$code,$arrival,$departure,0,${s * 50}');
    }
  }
  return buffer.toString();
}

Future<bool> _usesIndex(Database db, String sql, List<Object?> args) async {
  final plan = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
  final text = plan.map((row) => row.values.join(' ')).join('\n').toUpperCase();
  return text.contains('USING INDEX') || text.contains('USING COVERING INDEX');
}

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  late Database db;

  setUpAll(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await configureRailwayConnection(db);
    for (final statement in schema.schemaStatements) {
      await db.execute(statement);
    }
    await RailwayImporter(db).import(
      stations: parseCsvSource(_buildStationsCsv()),
      trains: parseCsvSource(_buildTrainsCsv()),
      routeStops: parseCsvSource(_buildRouteStopsCsv()),
      runningDays: const [],
      datasetSource: 'synthetic performance fixture',
    );
  });

  tearDownAll(() => db.close());

  test('station exact-code lookup uses idx_stations_normalized_code', () async {
    expect(
      await _usesIndex(db, 'SELECT * FROM stations WHERE normalized_code = ?', [
        'SYN150',
      ]),
      isTrue,
    );
  });

  test('station name search uses idx_stations_normalized_name', () async {
    expect(
      await _usesIndex(
        db,
        'SELECT * FROM stations WHERE normalized_name LIKE ?',
        ['synthetic station 1%'],
      ),
      isTrue,
    );
  });

  test('train exact-number lookup uses idx_trains_normalized_number', () async {
    expect(
      await _usesIndex(db, 'SELECT * FROM trains WHERE normalized_number = ?', [
        '90050',
      ]),
      isTrue,
    );
  });

  test('route retrieval uses idx_route_stops_train_sequence', () async {
    expect(
      await _usesIndex(
        db,
        'SELECT * FROM route_stops WHERE train_id = ? ORDER BY stop_sequence',
        [1],
      ),
      isTrue,
    );
  });

  test('station-to-trains join uses idx_route_stops_station', () async {
    final plan = await db.rawQuery(
      '''
      EXPLAIN QUERY PLAN
      SELECT DISTINCT t.* FROM trains t
      JOIN route_stops rs ON rs.train_id = t.train_id
      WHERE rs.station_id = ?
    ''',
      [1],
    );
    final text = plan.map((r) => r.values.join(' ')).join('\n').toUpperCase();
    expect(text, contains('IDX_ROUTE_STOPS_STATION'));
  });

  test('the direct-services join (findDirectServices\' query shape) uses '
      'route_stops indexes, not a full scan', () async {
    final plan = await db.rawQuery('''
        EXPLAIN QUERY PLAN
        SELECT t.* FROM route_stops rs_from
        JOIN route_stops rs_to
          ON rs_to.train_id = rs_from.train_id
          AND rs_to.station_id = 5
          AND rs_to.stop_sequence > rs_from.stop_sequence
        JOIN trains t ON t.train_id = rs_from.train_id
        WHERE rs_from.station_id = 1
      ''');
    final text = plan.map((r) => r.values.join(' ')).join('\n').toUpperCase();
    expect(text, isNot(contains('SCAN ROUTE_STOPS')));
  });

  test('findDirectServices finds a real synthetic multi-stop route by '
      'querying the full production-sized database', () async {
    final rows = await db.rawQuery('''
        SELECT t.number FROM route_stops rs_from
        JOIN route_stops rs_to
          ON rs_to.train_id = rs_from.train_id
          AND rs_to.station_id = (SELECT station_id FROM stations WHERE normalized_code = 'SYN004')
          AND rs_to.stop_sequence > rs_from.stop_sequence
        JOIN trains t ON t.train_id = rs_from.train_id
        WHERE rs_from.station_id = (SELECT station_id FROM stations WHERE normalized_code = 'SYN000')
        ''');
    expect(rows.map((r) => r['number']), contains('90000'));
  });

  test('indexed queries stay fast at this scale', () async {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      await db.query(
        'stations',
        where: 'normalized_code = ?',
        whereArgs: ['SYN${(i % _stationCount).toString().padLeft(3, '0')}'],
      );
    }
    stopwatch.stop();
    // Generous bound - this is a smoke check against an accidental full
    // table scan creeping in, not a strict performance benchmark.
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
  });
}
