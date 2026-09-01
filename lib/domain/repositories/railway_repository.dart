import '../entities/dataset_metadata.dart';
import '../entities/route_stop.dart';
import '../entities/running_days.dart';
import '../entities/station.dart';
import '../entities/train_service.dart';

/// The one abstraction future features (station search, train search,
/// train details, journey discovery) are built against. UI code and
/// higher-level services must depend on this interface, never on
/// `sqflite`/SQL directly - see
/// `lib/data/repositories/sqlite_railway_repository.dart` for the only
/// implementation.
abstract interface class RailwayRepository {
  /// Matches [query] against station codes and names (see
  /// [RailwayNormalization]). Returns at most [limit] results - callers
  /// must not assume this returns every match.
  Future<List<Station>> searchStations(String query, {int limit = 20});

  /// Exact match on station code (case-insensitive). `null` if no such
  /// station exists in the current dataset.
  Future<Station?> getStationByCode(String code);

  /// Matches [query] against train numbers and names. Returns at most
  /// [limit] results.
  Future<List<TrainService>> searchTrains(String query, {int limit = 20});

  /// Exact match on train number (case-insensitive). `null` if no such
  /// train exists in the current dataset.
  Future<TrainService?> getTrainByNumber(String number);

  /// The full route of [trainId], ordered by stop sequence. Empty list
  /// if the train has no route stops recorded.
  Future<List<RouteStop>> getRoute(int trainId);

  /// Trains that stop at [stationId], most-relevant/likely first as
  /// defined by the implementation. Returns at most [limit] results.
  Future<List<TrainService>> getTrainsAtStation(
    int stationId, {
    int limit = 50,
  });

  /// The operating-day calendar for [trainId]. `null` if the dataset
  /// records nothing at all for this train (as opposed to a
  /// [RunningDays] with [DataConfidence.unknown], which means "recorded
  /// but not authoritative").
  Future<RunningDays?> getRunningDays(int trainId);

  /// Provenance/versioning of the currently loaded dataset.
  Future<DatasetMetadata> getDatasetMetadata();
}
