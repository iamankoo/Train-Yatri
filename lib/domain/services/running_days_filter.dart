import '../entities/connecting_journey.dart';
import '../entities/data_confidence.dart';
import '../repositories/railway_repository.dart';
import 'journey_discovery_service.dart';

/// Removes a direct service or connecting-journey leg from
/// [JourneyDiscoveryResult] only when the static `running_days` table
/// (Block 6's 2026 dataset) *positively confirms* that train does not
/// operate on [weekday] - never merely because the dataset has no
/// running-days data for it (see `RunningDays.confidence`:
/// [DataConfidence.unknown] means "no data", not "doesn't run", and
/// must leave the service visible exactly as Journey Search has always
/// shown it). This is a distinct, additive layer on top of the existing
/// offline "these routes exist" search - see
/// `docs/RUNNING_DAYS_BACKFILL.md` for the separate RailRadar-backed
/// "Running on `<date>`" section, which this does not replace.
///
/// A connecting journey is dropped only if a *confirmed* running-days
/// record says either leg does not run on [weekday] - both legs must
/// actually operate for the connection to be valid that day.
class RunningDaysFilter {
  const RunningDaysFilter._();

  static Future<JourneyDiscoveryResult> apply({
    required RailwayRepository repository,
    required JourneyDiscoveryResult result,
    required int weekday,
  }) async {
    final trainIds = <int>{
      for (final service in result.direct) service.train.trainId,
      for (final journey in result.connecting) ...[
        journey.legA.train.trainId,
        journey.legB.train.trainId,
      ],
    };
    if (trainIds.isEmpty) return result;

    final confirmedNotRunning = <int>{};
    for (final trainId in trainIds) {
      final runningDays = await repository.getRunningDays(trainId);
      if (runningDays != null &&
          runningDays.confidence == DataConfidence.confirmed &&
          !runningDays.operatesOnWeekday(weekday)) {
        confirmedNotRunning.add(trainId);
      }
    }
    if (confirmedNotRunning.isEmpty) return result;

    final direct = [
      for (final service in result.direct)
        if (!confirmedNotRunning.contains(service.train.trainId)) service,
    ];
    final connecting = <ConnectingJourney>[
      for (final journey in result.connecting)
        if (!confirmedNotRunning.contains(journey.legA.train.trainId) &&
            !confirmedNotRunning.contains(journey.legB.train.trainId))
          journey,
    ];
    return JourneyDiscoveryResult(direct: direct, connecting: connecting);
  }
}
