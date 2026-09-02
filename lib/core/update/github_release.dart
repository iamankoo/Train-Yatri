/// One downloadable file attached to a GitHub Release - as much of the
/// GitHub API's own `assets[]` shape as this project actually uses.
final class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  @override
  String toString() => 'ReleaseAsset($name, $sizeBytes bytes)';
}

/// A GitHub Release, as returned by
/// `GET /repos/{owner}/{repo}/releases/latest` - only the fields this
/// project's update checker needs.
final class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.htmlUrl,
    required this.assets,
  });

  /// e.g. "v0.4.0" - the release's own version identity.
  final String tagName;

  /// The release's public GitHub page - never anything the app writes
  /// to, only ever shown/linked to a user for context.
  final String htmlUrl;

  final List<ReleaseAsset> assets;
}
