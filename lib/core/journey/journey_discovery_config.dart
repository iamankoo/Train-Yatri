/// Bounds and tuning constants for `JourneyDiscoveryService` (Block 5).
///
/// Every default here is a deliberately conservative journey-*planning*
/// heuristic, not a railway guarantee - see
/// [minimumConnectionBufferMinutes]'s own doc for what that means in
/// practice. All fields are configurable (rather than hard-coded
/// constants inline in the service) so a future block - or a test -
/// can tune them without editing the algorithm itself.
final class JourneyDiscoveryConfig {
  const JourneyDiscoveryConfig({
    this.maxFirstLegCandidates = 8,
    this.maxInterchangeCandidates = 25,
    this.maxSecondLegCandidatesPerInterchange = 5,
    this.maxConnectingResults = 10,
    this.minimumConnectionBufferMinutes = 30,
  }) : assert(maxFirstLegCandidates > 0),
       assert(maxInterchangeCandidates > 0),
       assert(maxSecondLegCandidatesPerInterchange > 0),
       assert(maxConnectingResults > 0),
       assert(minimumConnectionBufferMinutes >= 0);

  /// How many candidate first-leg trains (departing FROM, earliest
  /// first) are considered at all. Bounds the number of
  /// `getRouteWithStations` calls the search makes to one per
  /// candidate.
  final int maxFirstLegCandidates;

  /// Total number of candidate interchange stations examined *across
  /// all* first-leg candidates combined (not per-train) - the single
  /// budget that keeps a first-leg train with an unusually long route
  /// from dominating the search. Bounds the number of
  /// `findDirectServices` calls the search makes to at most this many.
  final int maxInterchangeCandidates;

  /// How many second-leg train candidates are considered per
  /// interchange station (passed straight through as `limit` to
  /// `findDirectServices`).
  final int maxSecondLegCandidatesPerInterchange;

  /// How many `ConnectingJourney` results are returned after ranking,
  /// regardless of how many valid candidates were found.
  final int maxConnectingResults;

  /// The minimum time (`legB` departure minus `legA` arrival at the
  /// interchange) a connection must have to be offered at all - a
  /// journey-*planning* heuristic to avoid suggesting a transfer no
  /// real passenger could make, **not** a claim that this buffer
  /// guarantees a successful connection: this static dataset has no
  /// platform, walking-distance, or delay information, and Indian
  /// Railways gives no such guarantee either. 30 minutes is a
  /// deliberately conservative default for an unfamiliar station.
  final int minimumConnectionBufferMinutes;

  static const defaults = JourneyDiscoveryConfig();
}
