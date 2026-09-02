/// A minimal major.minor.patch semantic version, comparable so the
/// update checker can decide "is the latest GitHub Release newer than
/// what's installed" without pulling in a whole semver package for
/// three integers.
///
/// Deliberately ignores build metadata (a trailing `+N`, as Flutter's
/// own `pubspec.yaml` `version:` field uses for the Android
/// `versionCode`) and pre-release suffixes (`-beta.1`) - this project's
/// own releases don't use them, and silently mis-comparing an unplanned
/// one is worse than just not supporting it yet.
final class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  final int major;
  final int minor;
  final int patch;

  /// Parses a version string, tolerating a leading `v` (GitHub Release
  /// tags here are `v0.4.0`) and a trailing build-metadata suffix
  /// (`+2`, as `flutter.versionName` derives from `pubspec.yaml`'s
  /// `0.4.0+4`). Returns `null` - never a guessed/zeroed version - if
  /// [raw] isn't a recognizable `major.minor.patch`.
  static SemanticVersion? tryParse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plusIndex = value.indexOf('+');
    if (plusIndex != -1) value = value.substring(0, plusIndex);
    final dashIndex = value.indexOf('-');
    if (dashIndex != -1) value = value.substring(0, dashIndex);

    final parts = value.split('.');
    if (parts.length != 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    return SemanticVersion(major: major, minor: minor, patch: patch);
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemanticVersion &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
