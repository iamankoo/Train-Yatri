/// How much the imported dataset itself vouches for a piece of data.
///
/// This exists specifically so the app can be honest about data it is
/// not sure of (most importantly running-day/calendar data, which many
/// open railway datasets do not source authoritatively) instead of
/// silently presenting it with the same confidence as verified fields.
enum DataConfidence {
  /// The source dataset explicitly and authoritatively provided this
  /// value.
  confirmed,

  /// The value is absent, inferred, or the source's authority over it
  /// is not established. The app must not present this with the same
  /// certainty as [confirmed] data.
  unknown,
}
