/// Deterministic normalization for railway search matching.
///
/// Used both by the import pipeline (to populate the `normalized_*`
/// columns queries actually search against) and by the repository (to
/// normalize a user's query the same way) - so a query and a stored
/// value normalize identically by construction. No fuzzy or AI-based
/// matching: every rule here is a fixed, explainable transformation.
abstract final class RailwayNormalization {
  /// Case-insensitive, whitespace-collapsed matching for free-text
  /// names ("New   Delhi" and "new delhi" normalize the same).
  static String normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Station/train codes and numbers are matched case-insensitively but
  /// otherwise verbatim (no internal whitespace is expected or
  /// collapsed away, since e.g. a train number is a single token).
  static String normalizeCode(String value) {
    return value.trim().toUpperCase();
  }
}
