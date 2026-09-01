// Exercises the exact path the real running app takes: RailwayDatabase
// loading assets/database/railway.db through Flutter's real asset
// bundle (rootBundle), not an injected fake asset loader - the one
// thing test/data/database/railway_database_test.dart deliberately
// does NOT cover, since it only proves the copy/versioning mechanism
// in isolation. Skips itself if the asset hasn't been built.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/railway_database.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';

import '../test_support/ffi_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureSqfliteFfiInitialized);

  final dbExists = File('assets/database/railway.db').existsSync();

  test(
    'RailwayDatabase loads the real bundled asset via rootBundle, '
    'copies it once, and the repository can query real data through it',
    () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final scratch = Directory.systemTemp.createTempSync(
        'railway_real_asset_test_',
      );
      addTearDown(() {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      });

      final database = RailwayDatabase(
        databaseFactory: databaseFactoryFfi,
        databasesDirectory: () async => scratch.path,
        // assetLoader intentionally NOT overridden - this uses the
        // real rootBundle.load('assets/database/railway.db'), the same
        // call the actual app makes.
      );
      addTearDown(database.close);

      final db = await database.open();
      final repository = SqliteRailwayRepository(db);

      final station = await repository.getStationByCode('NDLS');
      expect(station, isNotNull);
      expect(station!.name, 'NEW DELHI');

      final metadata = await repository.getDatasetMetadata();
      expect(metadata.stationCount, greaterThan(8000));
    },
  );
}
