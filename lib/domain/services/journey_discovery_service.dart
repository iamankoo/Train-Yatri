import '../../core/journey/journey_discovery_config.dart';
import '../entities/connecting_journey.dart';
import '../entities/direct_service.dart';
import '../entities/station.dart';
import '../repositories/railway_repository.dart';

/// Direct services and one-change connecting journeys found for a
/// single FROM/TO search - what `SearchResultsScreen` (Block 5) renders
/// as its "DIRECT" and "1 CHANGE" sections.
final class JourneyDiscoveryResult {
  const JourneyDiscoveryResult({
    required this.direct,
    required this.connecting,
  });

  final List<DirectService> direct;
  final List<ConnectingJourney> connecting;

  bool get isEmpty => direct.isEmpty && connecting.isEmpty;
}

/// Block 5's deterministic journey-discovery algorithm: direct services
/// (delegated straight to `RailwayRepository.findDirectServices`, kept
/// from Block 3) plus a bounded one-change connecting-journey search
/// built entirely from existing indexed repository queries - no new
/// complex SQL, no third-party routing engine, no AI.
///
/// ## The connecting-journey search, precisely
///
/// 1. **Candidate first legs**: `repository.findDepartures(fromStationId,
///    limit: config.maxFirstLegCandidates)` - trains departing FROM,
///    earliest first.
/// 2. For each, `repository.getRouteWithStations(trainId)` (already
///    used by Train Details, Block 4) gives that train's full route;
///    every stop after FROM (excluding FROM and TO themselves) is a
///    candidate interchange station.
/// 3. **Candidate second legs**: for each candidate interchange (up to
///    `config.maxInterchangeCandidates` total, spent across *all*
///    first-leg candidates combined - see
///    [JourneyDiscoveryConfig.maxInterchangeCandidates]),
///    `repository.findDirectServices(fromStationId: interchange, toStationId,
///    limit: config.maxSecondLegCandidatesPerInterchange)` reuses the
///    exact same query direct search already relies on.
/// 4. **Validation** (a candidate failing any of these is silently
///    dropped, never surfaced as an error - see [_buildConnection]):
///    same train used for both legs; either leg's own duration missing
///    or negative (mirrors [DirectService.journeyDuration]'s own
///    honesty rule); insufficient connection buffer.
/// 5. **Ranking**: earliest arrival at TO, then shortest total
///    duration, then shortest wait, then fewest stops - all computed
///    from fields the dataset actually has, never a subjective/AI
///    score (see `_rank`).
/// 6. Truncated to `config.maxConnectingResults`.
///
/// Worst case this issues `maxFirstLegCandidates` `findDepartures`-then-
/// `getRouteWithStations` pairs plus up to `maxInterchangeCandidates`
/// `findDirectServices` calls - with the defaults, at most on the order
/// of 40 total indexed SQL queries per search, never a full-table scan
/// or an in-memory graph search.
abstract final class JourneyDiscoveryService {
  static Future<JourneyDiscoveryResult> discover({
    required RailwayRepository repository,
    required int fromStationId,
    required int toStationId,
    JourneyDiscoveryConfig config = JourneyDiscoveryConfig.defaults,
  }) async {
    // Block 5, "Same station": never run a journey search for FROM ==
    // TO. The UI already refuses to start one (JourneySearchState.isValid),
    // but this guards the service directly too - without it, a
    // "go out on one train, come back on a different one" combination
    // could otherwise surface as a nonsensical "connection" from a
    // station to itself.
    if (fromStationId == toStationId) {
      return const JourneyDiscoveryResult(direct: [], connecting: []);
    }

    final direct = await repository.findDirectServices(
      fromStationId: fromStationId,
      toStationId: toStationId,
    );

    final connecting = await _discoverConnections(
      repository: repository,
      fromStationId: fromStationId,
      toStationId: toStationId,
      config: config,
    );

    return JourneyDiscoveryResult(direct: direct, connecting: connecting);
  }

  static Future<List<ConnectingJourney>> _discoverConnections({
    required RailwayRepository repository,
    required int fromStationId,
    required int toStationId,
    required JourneyDiscoveryConfig config,
  }) async {
    final firstLegs = await repository.findDepartures(
      fromStationId,
      limit: config.maxFirstLegCandidates,
    );

    final results = <ConnectingJourney>[];
    // (trainA, interchange, trainB) already produced - a real route
    // could in principle list the same station twice, or two
    // first-leg candidates could share an interchange; never offer the
    // exact same connection twice (Block 5 edge case: "duplicate
    // candidates").
    final seen = <(int, int, int)>{};
    var interchangeBudget = config.maxInterchangeCandidates;

    for (final firstLeg in firstLegs) {
      if (interchangeBudget <= 0) break;

      final route = await repository.getRouteWithStations(
        firstLeg.train.trainId,
      );

      for (final candidate in route) {
        if (interchangeBudget <= 0) break;
        final stationId = candidate.station.stationId;
        // The interchange must be a real intermediate stop strictly
        // after FROM, and neither FROM nor TO itself - reaching TO on
        // this same train is a direct service, already covered above;
        // a route re-visiting FROM would not be a sensible transfer
        // point either.
        if (candidate.stop.stopSequence <= firstLeg.stop.stopSequence) {
          continue;
        }
        if (stationId == toStationId || stationId == fromStationId) {
          continue;
        }
        interchangeBudget--;

        final legA = DirectService(
          train: firstLeg.train,
          fromStop: firstLeg.stop,
          toStop: candidate.stop,
        );

        final secondLegs = await repository.findDirectServices(
          fromStationId: stationId,
          toStationId: toStationId,
          limit: config.maxSecondLegCandidatesPerInterchange,
        );

        for (final legB in secondLegs) {
          if (legB.train.trainId == firstLeg.train.trainId) {
            continue; // same-train rejection
          }
          final key = (firstLeg.train.trainId, stationId, legB.train.trainId);
          if (!seen.add(key)) continue;

          final connection = _buildConnection(
            legA: legA,
            interchange: candidate.station,
            legB: legB,
            minimumBufferMinutes: config.minimumConnectionBufferMinutes,
          );
          if (connection != null) results.add(connection);
        }
      }
    }

    results.sort(_compareConnections);
    return results.take(config.maxConnectingResults).toList();
  }

  /// `null` if the candidate fails any validation - see the class-level
  /// doc's step 4. Never throws, never fabricates a missing time.
  static ConnectingJourney? _buildConnection({
    required DirectService legA,
    required Station interchange,
    required DirectService legB,
    required int minimumBufferMinutes,
  }) {
    // legA's own elapsed time from FROM to the interchange - reuses
    // DirectService.journeyDuration's existing day_offset-aware,
    // negative-duration-rejecting logic rather than re-deriving it.
    final legAElapsed = legA.journeyDuration;
    if (legAElapsed == null) return null;

    final departureClock = legB.fromStop.departureTime;
    if (departureClock == null) return null;

    final legBElapsed = legB.journeyDuration;
    if (legBElapsed == null) return null;

    // legA and legB are two *different* trains, each with its own
    // day_offset numbering relative to its own origin - there is no
    // shared calendar to compare them on directly. The only honest
    // anchor is clock time, computed in minutes *midnight-anchored to
    // legA's own origin's day_offset 0* (never "minutes elapsed since
    // boarding", which would misalign with clock-time comparisons
    // whenever boarding itself isn't exactly at midnight - a real bug
    // caught and fixed while writing this): legB is treated as
    // departing the interchange at its recorded clock time on the
    // earliest day (relative to that same anchor) that is still at or
    // after legA's arrival there plus the buffer - never silently
    // assumed to carry over an extra day beyond that, which would
    // invent a day-of-week/operating-calendar fact this dataset does
    // not have.
    final departureAtFromAbsMinutes =
        legA.fromStop.dayOffset * 1440 +
        legA.fromStop.departureTime!.minutesSinceMidnight;
    final arrivalAtInterchangeAbsMinutes =
        legA.toStop.dayOffset * 1440 +
        legA.toStop.arrivalTime!.minutesSinceMidnight;
    final arrivalDayIndex = arrivalAtInterchangeAbsMinutes ~/ 1440;
    final departureAtInterchangeAbsMinutes =
        arrivalDayIndex * 1440 + departureClock.minutesSinceMidnight;

    if (departureAtInterchangeAbsMinutes <
        arrivalAtInterchangeAbsMinutes + minimumBufferMinutes) {
      return null; // insufficient connection buffer (or already departed)
    }

    final arrivalAtToAbsMinutes =
        departureAtInterchangeAbsMinutes + legBElapsed.inMinutes;

    return ConnectingJourney(
      legA: legA,
      interchange: interchange,
      legB: legB,
      waitingDuration: Duration(
        minutes:
            departureAtInterchangeAbsMinutes - arrivalAtInterchangeAbsMinutes,
      ),
      totalDuration: Duration(
        minutes: arrivalAtToAbsMinutes - departureAtFromAbsMinutes,
      ),
    );
  }

  /// Deterministic ranking (Block 5, "Connection Quality"): earliest
  /// arrival at TO, then shortest total duration, then shortest wait,
  /// then fewest stops. "Arrival at TO" is measured relative to each
  /// candidate's own first-leg departure from FROM (day_offset/time as
  /// recorded on that stop) plus its total duration - the same
  /// "different trains' day_offsets are directly comparable for
  /// ordering purposes" convention `findDirectServices`'s own
  /// `ORDER BY` already uses for direct results, applied consistently
  /// here rather than inventing a second convention.
  static int _compareConnections(ConnectingJourney a, ConnectingJourney b) {
    int arrivalKey(ConnectingJourney c) {
      final departure = c.legA.fromStop.departureTime;
      final boardingAbsoluteMinutes = (departure == null)
          ? 0
          : c.legA.fromStop.dayOffset * 1440 + departure.minutesSinceMidnight;
      return boardingAbsoluteMinutes + c.totalDuration.inMinutes;
    }

    final byArrival = arrivalKey(a).compareTo(arrivalKey(b));
    if (byArrival != 0) return byArrival;

    final byDuration = a.totalDuration.compareTo(b.totalDuration);
    if (byDuration != 0) return byDuration;

    final byWait = a.waitingDuration.compareTo(b.waitingDuration);
    if (byWait != 0) return byWait;

    return a.totalStops.compareTo(b.totalStops);
  }
}
