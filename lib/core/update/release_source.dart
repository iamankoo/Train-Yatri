import 'dart:convert';
import 'dart:io';

import 'github_release.dart';

/// Where the update checker gets "what is the latest release" from.
/// Abstracted so the checker/UI can be tested with a fake instead of a
/// real network call, and so this project's "no embedded credentials"
/// rule is enforced by construction - nothing implementing this can
/// require a secret to be handed in.
abstract interface class ReleaseSource {
  /// The latest release, or `null` if it genuinely could not be
  /// determined (offline, GitHub unreachable, unexpected response) -
  /// never a fabricated/cached-forever fallback. Callers must treat
  /// `null` as "skip the update check silently", never as an error to
  /// surface to the user.
  Future<GitHubRelease?> getLatestRelease();
}

/// Reads the latest release straight from GitHub's public REST API -
/// no authentication, no token, nothing but the repository's own public
/// release metadata (per Block 4's C5 requirement: no credentials
/// embedded in the app, HTTPS only).
class GitHubReleaseSource implements ReleaseSource {
  const GitHubReleaseSource({
    this.owner = 'iamankoo',
    this.repo = 'Train-Yatri',
    this.timeout = const Duration(seconds: 8),
  });

  final String owner;
  final String repo;
  final Duration timeout;

  @override
  Future<GitHubRelease?> getLatestRelease() async {
    final client = HttpClient();
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/releases/latest',
      );
      final request = await client.getUrl(uri).timeout(timeout);
      // GitHub's REST API rejects requests with no User-Agent (HTTP 403)
      // and this is a plain, non-secret client identifier - not a
      // credential.
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'TrainYatri-App')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tagName = json['tag_name'] as String?;
      if (tagName == null) return null;

      final rawAssets = (json['assets'] as List?) ?? const [];
      final assets = <ReleaseAsset>[
        for (final rawAsset in rawAssets)
          if (rawAsset case {
            'name': final String name,
            'browser_download_url': final String url,
            'size': final int size,
          })
            ReleaseAsset(name: name, downloadUrl: url, sizeBytes: size),
      ];

      return GitHubRelease(
        tagName: tagName,
        htmlUrl: json['html_url'] as String? ?? '',
        assets: assets,
      );
    } on Object {
      // Offline, DNS failure, timeout, malformed JSON - all of these
      // must fail gracefully (C6): no crash, no error surfaced, the
      // update check simply finds nothing this time.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
