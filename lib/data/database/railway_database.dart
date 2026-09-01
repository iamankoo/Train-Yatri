import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite/sqflite.dart'
    show Database, DatabaseException, DatabaseFactory;

import 'connection_setup.dart';
import 'schema.dart' as schema;

/// Opens the app's copy of the railway database, copying it out of the
/// Flutter asset bundle into a writable location on first use.
///
/// A bundled asset is read-only and (on Android) lives inside the APK's
/// compressed asset zip, which SQLite cannot open directly - it must be
/// copied to a real file on disk before `sqflite`/SQLite can use it.
/// This copy only happens once per [fileName]: subsequent calls to
/// [open] find the existing file and skip straight to opening it,
/// unless the copied file's own `schema_meta.schema_version` is behind
/// the [schema.schemaVersion] this code expects, in which case it is
/// treated as stale and replaced from the (presumably newer) bundled
/// asset - this app never migrates data in place, it only ever ships a
/// freshly-built database asset.
class RailwayDatabase {
  RailwayDatabase({
    DatabaseFactory? databaseFactory,
    Future<Uint8List> Function(String assetPath)? assetLoader,
    Future<String> Function()? databasesDirectory,
    this.assetPath = 'assets/database/railway.db',
    this.fileName = 'trainyatri_railway.db',
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _assetLoader = assetLoader ?? _loadAssetAsBytes,
       _databasesDirectory =
           databasesDirectory ??
           (databaseFactory ?? sqflite.databaseFactory).getDatabasesPath;

  final DatabaseFactory _databaseFactory;
  final Future<Uint8List> Function(String assetPath) _assetLoader;

  /// Where the writable copy of the database lives. Defaults to the
  /// database factory's own `getDatabasesPath()` (the real app's
  /// platform-provided app-data directory); overridable so tests can
  /// point this at an isolated temp directory instead of whatever a
  /// desktop FFI factory would otherwise use.
  final Future<String> Function() _databasesDirectory;

  /// Path of the pre-built database within the Flutter asset bundle.
  final String assetPath;

  /// Filename the database is copied to in the app's writable database
  /// directory.
  final String fileName;

  Database? _database;

  /// Opens (copying from the asset bundle first if needed) and returns
  /// the database. Safe to call repeatedly - the same open [Database]
  /// is reused once opened.
  Future<Database> open() async {
    final existing = _database;
    if (existing != null) return existing;

    final dbDir = await _databasesDirectory();
    final dbPath = p.join(dbDir, fileName);

    if (!File(dbPath).existsSync()) {
      await _copyFromAsset(dbDir, dbPath);
    }

    var db = await _databaseFactory.openDatabase(dbPath);
    await configureRailwayConnection(db);

    if (!await _hasCurrentSchemaVersion(db)) {
      await db.close();
      await File(dbPath).delete();
      await _copyFromAsset(dbDir, dbPath);
      db = await _databaseFactory.openDatabase(dbPath);
      await configureRailwayConnection(db);
    }

    _database = db;
    return db;
  }

  Future<void> _copyFromAsset(String dbDir, String dbPath) async {
    await Directory(dbDir).create(recursive: true);
    final bytes = await _assetLoader(assetPath);
    await File(dbPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  Future<bool> _hasCurrentSchemaVersion(Database db) async {
    try {
      final rows = await db.query(
        'schema_meta',
        columns: ['schema_version'],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      return (rows.first['schema_version'] as int) == schema.schemaVersion;
    } on DatabaseException {
      // schema_meta itself doesn't exist - not a database this code built.
      return false;
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

Future<Uint8List> _loadAssetAsBytes(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
