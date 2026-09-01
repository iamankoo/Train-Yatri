import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/railway_repository.dart';
import '../database/railway_database.dart';
import '../repositories/sqlite_railway_repository.dart';

/// One [RailwayDatabase] for the app's lifetime. Opening it (copying
/// the bundled asset out on first run) is the expensive part - kept
/// behind [railwayRepositoryProvider] below so the rest of the app
/// never touches it directly.
final railwayDatabaseProvider = Provider<RailwayDatabase>((ref) {
  final database = RailwayDatabase();
  ref.onDispose(database.close);
  return database;
});

/// The single [RailwayRepository] instance the whole app shares. A
/// [FutureProvider] because opening the database is asynchronous (first
/// launch: copy the asset to a writable file); Riverpod caches the
/// completed future, so this only actually runs once per app session -
/// widgets that `ref.watch` it after the first successful open get the
/// resolved value immediately, no repeated work.
final railwayRepositoryProvider = FutureProvider<RailwayRepository>((
  ref,
) async {
  final railwayDatabase = ref.watch(railwayDatabaseProvider);
  final db = await railwayDatabase.open();
  return SqliteRailwayRepository(db);
});
