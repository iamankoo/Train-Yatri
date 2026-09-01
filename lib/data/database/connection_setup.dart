import 'package:sqflite_common/sqlite_api.dart';

/// Pragmas every connection to a railway database must run, applied in
/// exactly one place so production ([RailwayDatabase]) and every test
/// that opens its own connection stay identical.
Future<void> configureRailwayConnection(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');

  // stations.normalized_code/normalized_name and trains.normalized_number/
  // normalized_name are already normalized to one canonical case at
  // write time (see RailwayNormalization) and queries normalize their
  // input the same way before searching - so the two sides of every
  // `normalized_x LIKE ?` comparison are always already case-matched.
  // SQLite's LIKE-to-index-range-scan optimization is disabled by
  // default specifically because LIKE is case-INsensitive by default
  // while a plain index is case-sensitive (BINARY collation); turning
  // LIKE case-sensitive here removes that mismatch and lets the
  // planner use idx_stations_normalized_name / idx_trains_normalized_name
  // instead of a full table scan, without losing any matching power
  // (both sides were already the same case regardless).
  await db.execute('PRAGMA case_sensitive_like = ON');
}
