import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/railway_database.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;

import '../test_support/ffi_setup.dart';

/// Builds the bytes of a tiny, valid, already-imported railway
/// database - standing in for "the asset the app would ship" without
/// needing a real dataset.
Future<Uint8List> _buildFakeAssetBytes(Directory scratch) async {
  final path = '${scratch.path}/fake_asset_source.db';
  final db = await databaseFactoryFfi.openDatabase(path);
  for (final statement in schema.schemaStatements) {
    await db.execute(statement);
  }
  await db.insert('schema_meta', {
    'id': 1,
    'schema_version': schema.schemaVersion,
    'dataset_source': 'fake test asset',
    'dataset_version': null,
    'imported_at': DateTime.now().toIso8601String(),
    'station_count': 0,
    'train_count': 0,
    'route_stop_count': 0,
  });
  await db.close();
  final bytes = await File(path).readAsBytes();
  await File(path).delete();
  return bytes;
}

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('railway_db_test_');
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('copies the asset out and opens it', () async {
    final assetBytes = await _buildFakeAssetBytes(scratch);
    var loadCount = 0;

    final database = RailwayDatabase(
      databaseFactory: databaseFactoryFfi,
      databasesDirectory: () async => scratch.path,
      assetLoader: (_) async {
        loadCount++;
        return assetBytes;
      },
    );
    addTearDown(database.close);

    final db = await database.open();
    final rows = await db.query('schema_meta');

    expect(loadCount, 1);
    expect(rows.single['dataset_source'], 'fake test asset');
    expect(File('${scratch.path}/trainyatri_railway.db').existsSync(), isTrue);
  });

  test('does not re-copy the asset on a subsequent app start', () async {
    final assetBytes = await _buildFakeAssetBytes(scratch);
    var loadCount = 0;
    Future<Uint8List> loader(String _) async {
      loadCount++;
      return assetBytes;
    }

    final first = RailwayDatabase(
      databaseFactory: databaseFactoryFfi,
      databasesDirectory: () async => scratch.path,
      assetLoader: loader,
    );
    await first.open();
    await first.close();

    // A fresh instance, as if the app had been fully restarted.
    final second = RailwayDatabase(
      databaseFactory: databaseFactoryFfi,
      databasesDirectory: () async => scratch.path,
      assetLoader: loader,
    );
    addTearDown(second.close);
    await second.open();

    expect(loadCount, 1, reason: 'the asset must only be copied once');
  });

  test(
    'replaces a stale on-disk copy whose schema_version is behind',
    () async {
      // Simulate an old copy already on disk from a previous app version.
      final oldDbPath = '${scratch.path}/trainyatri_railway.db';
      final oldDb = await databaseFactoryFfi.openDatabase(oldDbPath);
      await oldDb.execute('''
      CREATE TABLE schema_meta (
        id INTEGER PRIMARY KEY,
        schema_version INTEGER NOT NULL,
        dataset_source TEXT NOT NULL,
        dataset_version TEXT,
        imported_at TEXT NOT NULL,
        station_count INTEGER NOT NULL,
        train_count INTEGER NOT NULL,
        route_stop_count INTEGER NOT NULL
      )
    ''');
      await oldDb.insert('schema_meta', {
        'id': 1,
        'schema_version': schema.schemaVersion - 1,
        'dataset_source': 'stale',
        'dataset_version': null,
        'imported_at': DateTime.now().toIso8601String(),
        'station_count': 0,
        'train_count': 0,
        'route_stop_count': 0,
      });
      await oldDb.close();

      final freshAssetBytes = await _buildFakeAssetBytes(scratch);

      final database = RailwayDatabase(
        databaseFactory: databaseFactoryFfi,
        databasesDirectory: () async => scratch.path,
        assetLoader: (_) async => freshAssetBytes,
      );
      addTearDown(database.close);

      final db = await database.open();
      final rows = await db.query('schema_meta');

      expect(rows.single['schema_version'], schema.schemaVersion);
      expect(rows.single['dataset_source'], 'fake test asset');
    },
  );
}
