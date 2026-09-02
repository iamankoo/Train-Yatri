import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entities/data_confidence.dart';
import '../../domain/entities/dataset_metadata.dart';
import '../../domain/entities/direct_service.dart';
import '../../domain/entities/railway_time.dart';
import '../../domain/entities/route_stop.dart';
import '../../domain/entities/route_stop_with_station.dart';
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
  Future<List<RouteStopWithStation>> getRouteWithStations(int trainId) async {
    final rows = await db.rawQuery(
      '''
      SELECT rs.*, s.station_id AS s_station_id, s.code AS s_code,
        s.name AS s_name, s.city AS s_city, s.state AS s_state,
        s.latitude AS s_latitude, s.longitude AS s_longitude
      FROM route_stops rs
      JOIN stations s ON s.station_id = rs.station_id
      WHERE rs.train_id = ?
      ORDER BY rs.stop_sequence
      ''',
      [trainId],
    );
    return rows.map((row) {
      return RouteStopWithStation(
        stop: _routeStopFromRow(row),
        station: Station(
          stationId: row['s_station_id'] as int,
          code: row['s_code'] as String,
          name: row['s_name'] as String,
          city: row['s_city'] as String?,
          state: row['s_state'] as String?,
          latitude: row['s_latitude'] as double?,
          longitude: row['s_longitude'] as double?,
        ),
      );
    }).toList();
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

  @override
  Future<List<DirectService>> findDirectServices({
    required int fromStationId,
    required int toStationId,
    int limit = 50,
  }) async {
    if (fromStationId == toStationId) return const [];

    // rs_from is filtered first (uses idx_route_stops_station), then
    // joined to rs_to on the same train (idx_route_stops_train_station
    // / idx_route_stops_train_sequence) - stop_sequence, not time of
    // day, is what actually encodes "from occurs before to" along a
    // route, so that comparison is what enforces direction here.
    final rows = await db.rawQuery(
      '''
      SELECT
        t.train_id, t.number, t.name, t.is_active, t.confidence,
        rs_from.route_stop_id AS from_route_stop_id,
        rs_from.stop_sequence AS from_stop_sequence,
        rs_from.arrival_time AS from_arrival_time,
        rs_from.departure_time AS from_departure_time,
        rs_from.day_offset AS from_day_offset,
        rs_from.distance_km AS from_distance_km,
        rs_to.route_stop_id AS to_route_stop_id,
        rs_to.stop_sequence AS to_stop_sequence,
        rs_to.arrival_time AS to_arrival_time,
        rs_to.departure_time AS to_departure_time,
        rs_to.day_offset AS to_day_offset,
        rs_to.distance_km AS to_distance_km
      FROM route_stops rs_from
      JOIN route_stops rs_to
        ON rs_to.train_id = rs_from.train_id
        AND rs_to.station_id = ?
        AND rs_to.stop_sequence > rs_from.stop_sequence
      JOIN trains t ON t.train_id = rs_from.train_id
      WHERE rs_from.station_id = ?
      ORDER BY rs_from.day_offset, rs_from.departure_time
      LIMIT ?
      ''',
      [toStationId, fromStationId, limit],
    );

    return rows.map((row) {
      final train = TrainService(
        trainId: row['train_id'] as int,
        number: row['number'] as String,
        name: row['name'] as String,
        isActive: (row['is_active'] as int) == 1,
        confidence: (row['confidence'] as String) == 'confirmed'
            ? DataConfidence.confirmed
            : DataConfidence.unknown,
      );
      final fromStop = RouteStop(
        routeStopId: row['from_route_stop_id'] as int,
        trainId: train.trainId,
        stationId: fromStationId,
        stopSequence: row['from_stop_sequence'] as int,
        arrivalTime: RailwayTime.tryParse(row['from_arrival_time'] as String?),
        departureTime: RailwayTime.tryParse(
          row['from_departure_time'] as String?,
        ),
        dayOffset: row['from_day_offset'] as int,
        distanceKm: row['from_distance_km'] as double?,
      );
      final toStop = RouteStop(
        routeStopId: row['to_route_stop_id'] as int,
        trainId: train.trainId,
        stationId: toStationId,
        stopSequence: row['to_stop_sequence'] as int,
        arrivalTime: RailwayTime.tryParse(row['to_arrival_time'] as String?),
        departureTime: RailwayTime.tryParse(
          row['to_departure_time'] as String?,
        ),
        dayOffset: row['to_day_offset'] as int,
        distanceKm: row['to_distance_km'] as double?,
      );
      return DirectService(train: train, fromStop: fromStop, toStop: toStop);
    }).toList();
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
