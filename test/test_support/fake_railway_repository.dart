// Builds a real SqliteRailwayRepository backed by an in-memory SQLite
// database (via sqflite_common_ffi) populated with a small, clearly
// synthetic fixture - and an Override that plugs it into
// railwayRepositoryProvider for widget tests. Widget tests can't use
// the real `sqflite` platform-channel factory (no platform channel
// exists under `flutter_test`), so this is how screens that read
// railwayRepositoryProvider (station picker, search results, Home) get
// exercised for real rather than mocked out entirely.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';
import 'package:train_yatri/data/providers/railway_providers.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/repositories/railway_repository.dart';

bool _ffiInitialized = false;
void ensureFfiInitializedForWidgetTests() {
  if (_ffiInitialized) return;
  sqfliteFfiInit();
  _ffiInitialized = true;
}

const _stationsCsv = '''
code,name,city,state,latitude,longitude
NDA,New Delta Alpha,Delta City,Delta State,28.6,77.2
MCB,Mumbai Central Beta,Beta City,Beta State,19.0,72.8
JXN,Junction Gamma,,,,
''';

const _trainsCsv = '''
number,name,is_active
00101T,Test Overnight Express,1
00102T,Test Day Express,1
''';

// 00101T departs NDA at 23:50 day 0, arrives MCB at 00:10 day 1.
const _routeStopsCsv = '''
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
00101T,1,NDA,,23:50,0,0
00101T,2,JXN,23:59,23:59,0,50
00101T,3,MCB,00:10,,1,300
00102T,1,NDA,,09:00,0,0
00102T,2,MCB,15:00,,0,300
''';

/// Opens a fresh in-memory synthetic database and returns a
/// [RailwayRepository] over it, ready to pass directly to widgets under
/// test or to wrap in an [Override].
///
/// `singleInstance: false` is required here: sqflite caches/reuses a
/// connection by path, and `inMemoryDatabasePath` is the same literal
/// path every time - without this, every test in a file would silently
/// share (and deadlock on) the *same* in-memory database and its
/// leftover transaction state from the previous test.
Future<RailwayRepository> buildFakeRailwayRepository() async {
  ensureFfiInitializedForWidgetTests();
  // databaseFactoryFfiNoIsolate (not databaseFactoryFfi) specifically:
  // the isolate-hopping default factory's message-passing round trips
  // don't resolve reliably inside widget tests' FakeAsync-driven
  // pump()/pumpAndSettle() loop, and cause pumpAndSettle to time out.
  // Non-widget tests use databaseFactoryFfi fine since plain async
  // tests aren't pump-driven.
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await configureRailwayConnection(db);
  for (final statement in schema.schemaStatements) {
    await db.execute(statement);
  }
  await RailwayImporter(db).import(
    stations: parseCsvSource(_stationsCsv),
    trains: parseCsvSource(_trainsCsv),
    routeStops: parseCsvSource(_routeStopsCsv),
    runningDays: const [],
    datasetSource: 'synthetic widget-test fixture',
  );
  return SqliteRailwayRepository(db);
}

/// A [railwayRepositoryProvider] override wired to
/// [buildFakeRailwayRepository] - pass this into `ProviderScope(overrides: [...])`
/// in any widget test that renders something depending on the railway
/// repository. Closes its database when the overriding [ProviderScope]
/// is torn down.
Override fakeRailwayRepositoryOverride() {
  return railwayRepositoryProvider.overrideWith((ref) async {
    final repository = await buildFakeRailwayRepository();
    ref.onDispose(() => (repository as SqliteRailwayRepository).db.close());
    return repository;
  });
}
