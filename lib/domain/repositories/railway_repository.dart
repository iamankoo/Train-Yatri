import '../entities/dataset_metadata.dart';
import '../entities/direct_service.dart';
import '../entities/route_stop.dart';
import '../entities/route_stop_with_station.dart';
import '../entities/running_days.dart';
import '../entities/station.dart';
import '../entities/train_service.dart';
import '../entities/train_stop.dart';

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

  /// [getRoute], with each stop's [Station] already joined in - for the
  /// Train Details route timeline, which needs every stop's station
  /// name/code and would otherwise cost one extra lookup per stop on a
  /// route that can have 50+ of them. Same ordering/emptiness contract
  /// as [getRoute].
  Future<List<RouteStopWithStation>> getRouteWithStations(int trainId);

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

  /// Trains that stop at [fromStationId] and later - by route stop
  /// order, not merely "also somewhere on the route" - at
  /// [toStationId]. Ordered by departure time from [fromStationId].
  /// Returns at most [limit] results. Empty if no such train exists, or
  /// if [fromStationId] equals [toStationId].
  Future<List<DirectService>> findDirectServices({
    required int fromStationId,
    required int toStationId,
    int limit = 50,
  });

  /// Trains that depart [stationId] (i.e. have a recorded, non-null
  /// departure time there - a stop that's only ever a train's terminus
  /// is excluded, since nothing departs from it), earliest departure
  /// first (by `day_offset` then `departure_time`). Returns at most
  /// [limit] - the candidate-generation building block for
  /// `JourneyDiscoveryService`'s connecting-journey search (Block 5),
  /// not used by direct search.
  Future<List<TrainStop>> findDepartures(int stationId, {int limit = 20});
}
