import 'semantic_version.dart';

/// Foundation for a future minimum-supported-version / force-update
/// requirement (C7) - deliberately not enforced anywhere in Block 4.
/// [minimumSupportedVersion] exists purely so a later block has a
/// typed place to plug real configuration (e.g. a value fetched
/// alongside the release check, or from a remote config service) into,
/// without the update-check plumbing itself needing to change shape.
///
/// [UpdatePolicy.none] - the only instance actually used in this block
/// - has `minimumSupportedVersion: null`, meaning "no version is
/// currently forced"; nothing in this codebase reads this field to
/// block app usage yet.
final class UpdatePolicy {
  const UpdatePolicy({this.minimumSupportedVersion});

  /// `null` unless/until a future block wires up a real source for
  /// this. When set, the running app's version being below this would
  /// be the trigger for a mandatory (non-dismissible) update prompt -
  /// that UI does not exist yet; this field alone is not a feature.
  final SemanticVersion? minimumSupportedVersion;

  static const none = UpdatePolicy();

  bool isBelowMinimum(SemanticVersion installed) {
    final minimum = minimumSupportedVersion;
    if (minimum == null) return false;
    return installed < minimum;
  }
}
