import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/entities/railway_time.dart';
import '../../domain/services/railway_normalization.dart';
import '../database/schema.dart' as schema;
import 'csv_source.dart';
import 'import_report.dart';

/// Builds a fresh railway database from parsed source rows.
///
/// Assumes [db] is already open with [schema.schemaStatements] applied
/// (an empty schema) - this class only ever inserts, it does not create
/// tables. Import order matters: stations and trains are imported
/// first so route stops and running days can validate their foreign
/// keys in memory (and report a precise reason) rather than relying on
/// SQLite to reject them opaquely.
class RailwayImporter {
  RailwayImporter(this.db);

  final Database db;

  Future<ImportReport> import({
    required List<SourceRow> stations,
    required List<SourceRow> trains,
    required List<SourceRow> routeStops,
    required List<SourceRow> runningDays,
    required String datasetSource,
    String? datasetVersion,
  }) async {
    final stationIssues = <ImportIssue>[];
    final trainIssues = <ImportIssue>[];
    final routeStopIssues = <ImportIssue>[];
    final runningDaysIssues = <ImportIssue>[];

    final stationIdsByCode = <String, int>{};
    final trainIdByNormalizedNumber = <String, int>{};
    final seenRouteStopKeys = <String>{};

    await db.transaction((txn) async {
      // --- Stations ---
      for (final row in stations) {
        final code = row['code'];
        final name = row['name'];
        if (code == null || name == null) {
          stationIssues.add(
            ImportIssue(
              file: 'stations.csv',
              rowNumber: row.rowNumber,
              reason: 'missing required code/name',
            ),
          );
          continue;
        }
        final normalizedCode = RailwayNormalization.normalizeCode(code);
        if (stationIdsByCode.containsKey(normalizedCode)) {
          stationIssues.add(
            ImportIssue(
              file: 'stations.csv',
              rowNumber: row.rowNumber,
              reason: 'duplicate station code "$code"',
            ),
          );
          continue;
        }

        final latitude = _parseDouble(row['latitude']);
        final longitude = _parseDouble(row['longitude']);
        if ((row['latitude'] != null && latitude == null) ||
            (row['longitude'] != null && longitude == null)) {
          stationIssues.add(
            ImportIssue(
              file: 'stations.csv',
              rowNumber: row.rowNumber,
              reason: 'unparseable latitude/longitude',
            ),
          );
          continue;
        }

        final stationId = await txn.insert('stations', {
          'code': code,
          'name': name,
          'normalized_code': normalizedCode,
          'normalized_name': RailwayNormalization.normalizeName(name),
          'city': row['city'],
          'state': row['state'],
          'latitude': latitude,
          'longitude': longitude,
        });
        stationIdsByCode[normalizedCode] = stationId;
      }

      // --- Trains ---
      for (final row in trains) {
        final number = row['number'];
        final name = row['name'];
        if (number == null || name == null) {
          trainIssues.add(
            ImportIssue(
              file: 'trains.csv',
              rowNumber: row.rowNumber,
              reason: 'missing required number/name',
            ),
          );
          continue;
        }
        final normalizedNumber = RailwayNormalization.normalizeCode(number);
        if (trainIdByNormalizedNumber.containsKey(normalizedNumber)) {
          trainIssues.add(
            ImportIssue(
              file: 'trains.csv',
              rowNumber: row.rowNumber,
              reason: 'duplicate train number "$number"',
            ),
          );
          continue;
        }

        final isActiveRaw = row['is_active'];
        final isActive = isActiveRaw == null ? true : _parseBool(isActiveRaw);
        if (isActiveRaw != null && isActive == null) {
          trainIssues.add(
            ImportIssue(
              file: 'trains.csv',
              rowNumber: row.rowNumber,
              reason: 'unparseable is_active value "$isActiveRaw"',
            ),
          );
          continue;
        }

        final category = row['category'];
        final pairedTrainNumber = row['paired_train_number'];

        final trainId = await txn.insert('trains', {
          'number': number,
          'name': name,
          'normalized_number': normalizedNumber,
          'normalized_name': RailwayNormalization.normalizeName(name),
          'is_active': (isActive ?? true) ? 1 : 0,
          'confidence': 'unknown',
          'category': (category == null || category.isEmpty) ? null : category,
          'paired_train_number':
              (pairedTrainNumber == null || pairedTrainNumber.isEmpty)
              ? null
              : pairedTrainNumber,
        });
        trainIdByNormalizedNumber[normalizedNumber] = trainId;
      }

      // --- Route stops ---
      for (final row in routeStops) {
        final trainNumber = row['train_number'];
        final stationCode = row['station_code'];
        final stopSequenceRaw = row['stop_sequence'];
        if (trainNumber == null ||
            stationCode == null ||
            stopSequenceRaw == null) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason:
                  'missing required train_number/station_code/stop_sequence',
            ),
          );
          continue;
        }

        final trainId =
            trainIdByNormalizedNumber[RailwayNormalization.normalizeCode(
              trainNumber,
            )];
        if (trainId == null) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason: 'unknown train_number "$trainNumber"',
            ),
          );
          continue;
        }

        final stationId =
            stationIdsByCode[RailwayNormalization.normalizeCode(stationCode)];
        if (stationId == null) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason: 'unknown station_code "$stationCode"',
            ),
          );
          continue;
        }

        final stopSequence = int.tryParse(stopSequenceRaw);
        if (stopSequence == null || stopSequence < 1) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason: 'invalid stop_sequence "$stopSequenceRaw"',
            ),
          );
          continue;
        }

        final arrivalRaw = row['arrival_time'];
        final departureRaw = row['departure_time'];
        final arrival = RailwayTime.tryParse(arrivalRaw);
        final departure = RailwayTime.tryParse(departureRaw);
        if ((arrivalRaw != null && arrival == null) ||
            (departureRaw != null && departure == null)) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason: 'unparseable arrival/departure time',
            ),
          );
          continue;
        }

        final dayOffsetRaw = row['day_offset'];
        final dayOffset = dayOffsetRaw == null ? 0 : int.tryParse(dayOffsetRaw);
        if (dayOffsetRaw != null && (dayOffset == null || dayOffset < 0)) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason: 'invalid day_offset "$dayOffsetRaw"',
            ),
          );
          continue;
        }

        final distanceKm = _parseDouble(row['distance_km']);
        if (row['distance_km'] != null && distanceKm == null) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason: 'unparseable distance_km "${row['distance_km']}"',
            ),
          );
          continue;
        }

        // Checked last (only once every other field on this row has
        // already validated) so a row that fails validation never
        // consumes/pollutes a (train, stop_sequence) slot that a later,
        // genuinely valid row for the same slot could still use - and
        // so this count only ever reflects rows actually inserted.
        final dedupeKey = '$trainId:$stopSequence';
        if (!seenRouteStopKeys.add(dedupeKey)) {
          routeStopIssues.add(
            ImportIssue(
              file: 'route_stops.csv',
              rowNumber: row.rowNumber,
              reason:
                  'duplicate stop_sequence $stopSequence for train "$trainNumber"',
            ),
          );
          continue;
        }

        await txn.insert('route_stops', {
          'train_id': trainId,
          'station_id': stationId,
          'stop_sequence': stopSequence,
          'arrival_time': arrival?.toDbString(),
          'departure_time': departure?.toDbString(),
          'day_offset': dayOffset ?? 0,
          'distance_km': distanceKm,
        });
      }

      // --- Running days ---
      const dayColumns = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ];
      for (final row in runningDays) {
        final trainNumber = row['train_number'];
        if (trainNumber == null) {
          runningDaysIssues.add(
            ImportIssue(
              file: 'running_days.csv',
              rowNumber: row.rowNumber,
              reason: 'missing required train_number',
            ),
          );
          continue;
        }
        final trainId =
            trainIdByNormalizedNumber[RailwayNormalization.normalizeCode(
              trainNumber,
            )];
        if (trainId == null) {
          runningDaysIssues.add(
            ImportIssue(
              file: 'running_days.csv',
              rowNumber: row.rowNumber,
              reason: 'unknown train_number "$trainNumber"',
            ),
          );
          continue;
        }

        final dayValues = <String, bool>{};
        var invalidDay = false;
        for (final day in dayColumns) {
          final raw = row[day];
          final value = raw == null ? false : _parseBool(raw);
          if (raw != null && value == null) {
            runningDaysIssues.add(
              ImportIssue(
                file: 'running_days.csv',
                rowNumber: row.rowNumber,
                reason: 'unparseable $day value "$raw"',
              ),
            );
            invalidDay = true;
            break;
          }
          dayValues[day] = value ?? false;
        }
        if (invalidDay) continue;

        final confidenceRaw = row['confidence']?.toLowerCase();
        final confidence = confidenceRaw == 'confirmed'
            ? 'confirmed'
            : 'unknown';

        await txn.insert('running_days', {
          'train_id': trainId,
          for (final day in dayColumns) day: (dayValues[day]! ? 1 : 0),
          'confidence': confidence,
        });
      }
    });

    final importedAt = DateTime.now().toIso8601String();
    await db.delete('schema_meta');
    await db.insert('schema_meta', {
      'id': 1,
      'schema_version': schema.schemaVersion,
      'dataset_source': datasetSource,
      'dataset_version': datasetVersion,
      'imported_at': importedAt,
      'station_count': stationIdsByCode.length,
      'train_count': trainIdByNormalizedNumber.length,
      'route_stop_count': seenRouteStopKeys.length,
    });

    final integrityResult = await db.rawQuery('PRAGMA integrity_check');
    final integrityOk =
        integrityResult.length == 1 &&
        (integrityResult.first.values.first as String).toLowerCase() == 'ok';

    final pageCount = _firstIntValue(await db.rawQuery('PRAGMA page_count'));
    final pageSize = _firstIntValue(await db.rawQuery('PRAGMA page_size'));
    final runningDaysCount = _firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM running_days'),
    );

    return ImportReport(
      stationCount: stationIdsByCode.length,
      trainCount: trainIdByNormalizedNumber.length,
      routeStopCount: seenRouteStopKeys.length,
      runningDaysCount: runningDaysCount,
      rejectedStations: stationIssues,
      rejectedTrains: trainIssues,
      rejectedRouteStops: routeStopIssues,
      rejectedRunningDays: runningDaysIssues,
      integrityCheckPassed: integrityOk,
      databaseSizeBytes: pageCount * pageSize,
    );
  }

  double? _parseDouble(String? raw) =>
      raw == null ? null : double.tryParse(raw);

  bool? _parseBool(String raw) {
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
        return true;
      case '0':
      case 'false':
      case 'no':
        return false;
      default:
        return null;
    }
  }
}

/// `PRAGMA`/`SELECT COUNT(*)` style queries return exactly one row with
/// one column - this reads that value without needing the `sqflite`
/// package's `Sqflite.firstIntValue` helper (which isn't available
/// through the Flutter-independent `sqflite_common` API this file is
/// intentionally typed against).
int _firstIntValue(List<Map<String, Object?>> rows) {
  return rows.first.values.first as int;
}
