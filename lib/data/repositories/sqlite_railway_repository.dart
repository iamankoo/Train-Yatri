import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entities/data_confidence.dart';
import '../../domain/entities/dataset_metadata.dart';
import '../../domain/entities/railway_time.dart';
import '../../domain/entities/route_stop.dart';
import '../../domain/entities/running_days.dart';
import '../../domain/entities/station.dart';
import '../../domain/entities/train_service.dart';
import '../../domain/repositories/railway_repository.dart';
import '../../domain/services/railway_normalization.dart';

/// The only [RailwayRepository] implementation - all SQL for the
/// railway database lives here and nowhere else. Every query runs
/// against SQLite directly (via the indexes defined in
/// `lib/data/database/schema.dart`); nothing here loads the dataset
/// into Dart memory.
class SqliteRailwayRepository implements RailwayRepository {
  SqliteRailwayRepository(this.db);

  final Database db;

  @override
  Future<List<Station>> searchStations(String query, {int limit = 20}) async {
    final normalizedName = RailwayNormalization.normalizeName(query);
    if (normalizedName.isEmpty) return const [];
    // codes are stored upper-cased (normalizeCode) and names lower-cased
    // (normalizeName) - with the connection's case_sensitive_like turned
    // on (see connection_setup.dart, needed for these LIKEs to use their
    // indexes), each column must be matched against a query normalized
    // the same way that column itself is stored.
    final normalizedCode = RailwayNormalization.normalizeCode(query);

    final rows = await db.query(
      'stations',
      where: 'normalized_code LIKE ? OR normalized_name LIKE ?',
      whereArgs: ['$normalizedCode%', '$normalizedName%'],
      orderBy: 'normalized_code',
      limit: limit,
    );
    return rows.map(_stationFromRow).toList();
  }

  @override
  Future<Station?> getStationByCode(String code) async {
    final rows = await db.query(
      'stations',
      where: 'normalized_code = ?',
      whereArgs: [RailwayNormalization.normalizeCode(code)],
      limit: 1,
    );
    return rows.isEmpty ? null : _stationFromRow(rows.first);
  }

  @override
  Future<List<TrainService>> searchTrains(
    String query, {
    int limit = 20,
  }) async {
    final normalizedName = RailwayNormalization.normalizeName(query);
    if (normalizedName.isEmpty) return const [];
    final normalizedNumber = RailwayNormalization.normalizeCode(query);

    final rows = await db.query(
      'trains',
      where: 'normalized_number LIKE ? OR normalized_name LIKE ?',
      whereArgs: ['$normalizedNumber%', '$normalizedName%'],
      orderBy: 'normalized_number',
      limit: limit,
    );
    return rows.map(_trainFromRow).toList();
  }

  @override
  Future<TrainService?> getTrainByNumber(String number) async {
    final rows = await db.query(
      'trains',
      where: 'normalized_number = ?',
      whereArgs: [RailwayNormalization.normalizeCode(number)],
      limit: 1,
    );
    return rows.isEmpty ? null : _trainFromRow(rows.first);
  }

  @override
  Future<List<RouteStop>> getRoute(int trainId) async {
    final rows = await db.query(
      'route_stops',
      where: 'train_id = ?',
      whereArgs: [trainId],
      orderBy: 'stop_sequence',
    );
    return rows.map(_routeStopFromRow).toList();
  }

  @override
  Future<List<TrainService>> getTrainsAtStation(
    int stationId, {
    int limit = 50,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT t.*
      FROM trains t
      JOIN route_stops rs ON rs.train_id = t.train_id
      WHERE rs.station_id = ?
      ORDER BY t.normalized_number
      LIMIT ?
      ''',
      [stationId, limit],
    );
    return rows.map(_trainFromRow).toList();
  }

  @override
  Future<RunningDays?> getRunningDays(int trainId) async {
    final rows = await db.query(
      'running_days',
      where: 'train_id = ?',
      whereArgs: [trainId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RunningDays(
      trainId: row['train_id'] as int,
      monday: (row['monday'] as int) == 1,
      tuesday: (row['tuesday'] as int) == 1,
      wednesday: (row['wednesday'] as int) == 1,
      thursday: (row['thursday'] as int) == 1,
      friday: (row['friday'] as int) == 1,
      saturday: (row['saturday'] as int) == 1,
      sunday: (row['sunday'] as int) == 1,
      confidence: (row['confidence'] as String) == 'confirmed'
          ? DataConfidence.confirmed
          : DataConfidence.unknown,
    );
  }

  @override
  Future<DatasetMetadata> getDatasetMetadata() async {
    final rows = await db.query('schema_meta', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      throw StateError(
        'No dataset metadata found - this database was never imported.',
      );
    }
    final row = rows.first;
    return DatasetMetadata(
      schemaVersion: row['schema_version'] as int,
      datasetSource: row['dataset_source'] as String,
      datasetVersion: row['dataset_version'] as String?,
      importedAt: DateTime.parse(row['imported_at'] as String),
      stationCount: row['station_count'] as int,
      trainCount: row['train_count'] as int,
      routeStopCount: row['route_stop_count'] as int,
    );
  }

  Station _stationFromRow(Map<String, Object?> row) => Station(
    stationId: row['station_id'] as int,
    code: row['code'] as String,
    name: row['name'] as String,
    city: row['city'] as String?,
    state: row['state'] as String?,
    latitude: row['latitude'] as double?,
    longitude: row['longitude'] as double?,
  );

  TrainService _trainFromRow(Map<String, Object?> row) => TrainService(
    trainId: row['train_id'] as int,
    number: row['number'] as String,
    name: row['name'] as String,
    isActive: (row['is_active'] as int) == 1,
    confidence: (row['confidence'] as String) == 'confirmed'
        ? DataConfidence.confirmed
        : DataConfidence.unknown,
  );

  RouteStop _routeStopFromRow(Map<String, Object?> row) => RouteStop(
    routeStopId: row['route_stop_id'] as int,
    trainId: row['train_id'] as int,
    stationId: row['station_id'] as int,
    stopSequence: row['stop_sequence'] as int,
    arrivalTime: RailwayTime.tryParse(row['arrival_time'] as String?),
    departureTime: RailwayTime.tryParse(row['departure_time'] as String?),
    dayOffset: row['day_offset'] as int,
    distanceKm: row['distance_km'] as double?,
  );
}
