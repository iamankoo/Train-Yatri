# Android APK update system (Block 4; packaging updated in Block 5)

Train Yatri is distributed as a directly-installed APK via GitHub
Releases, not the Play Store (see the release process in this repo's own
history for why). Without a store, the app has to know when a newer
version exists and offer to fetch/install it itself - that's what this
document covers.

## Overview

```
Home screen (startup, non-blocking)
      |
      v
updateCheckProvider  --------->  GitHub Releases API
      |                          GET /repos/iamankoo/Train-Yatri/releases/latest
      | (UpdateInfo? - null means "nothing to offer",
      |  covering both "up to date" and "check failed")
      v
update-available dialog ("Train Yatri update available" / "Update now" / "Later")
      |
      v  (Update now)
download dialog (progress, size + optional SHA-256 verification, retry on failure)
      |
      v
Android's own package installer (ACTION_VIEW via FileProvider)
      |
      v
Android's own "install this app?" confirmation UI
```

Nothing in this pipeline ever installs silently - the last step is
always Android's own system confirmation, not this app.

## Source of truth: GitHub Releases

`lib/core/update/release_source.dart`'s `GitHubReleaseSource` calls the
public, unauthenticated GitHub REST API:

```
GET https://api.github.com/repos/iamankoo/Train-Yatri/releases/latest
```

No token, no credential, nothing but public release metadata (name,
asset list, asset download URLs, asset sizes) - satisfying the "no
embedded credentials" requirement. A `User-Agent` header is set only
because GitHub's API rejects requests without one; it identifies the
client as `TrainYatri-App`, nothing more.

Any failure - offline, DNS failure, non-200 response, malformed JSON,
timeout - is caught and treated as "no release found", never surfaced
as an app error. See `UpdateChecker` below for how that composes with
version comparison.

## Version comparison

`lib/core/update/semantic_version.dart` parses `major.minor.patch` out
of both the installed app's own version (via `package_info_plus`,
reading the real installed `versionName` - not a hand-duplicated Dart
constant that could drift from `pubspec.yaml`) and the release's own
tag name (`vX.Y.Z`, tolerating the leading `v` and stripping the
pubspec-style `+N` build number where relevant). Comparison is a plain
tuple compare; the app is offered an update only when
`latest > installed`, so a stale/older release tag (or a downgrade)
never gets suggested.

## Which APK: a single universal build (changed in v0.5.0)

Block 4 (v0.1.0-v0.4.0) shipped three ABI-specific APKs per release and
had the client pick one by `Abi.current()`. **From v0.5.0 on, every
release publishes exactly one universal APK** -
`train-yatri-vX.Y.Z.apk`, built via plain `flutter build apk --release`
(no `--split-per-abi`) - installable on any supported Android device.
`lib/core/update/apk_asset_selector.dart` simply picks the one asset
matching that exact filename pattern; there is no ABI detection left to
do. The v0.1.0-v0.4.0 per-ABI releases remain on GitHub exactly as
published (GitHub Releases are a permanent historical archive - old
assets are never deleted), but the update checker only ever looks at
the *latest* release, which from v0.5.0 on always has just this one
asset.

## Download, validation and retry (C3)

`lib/core/update/apk_downloader.dart`'s `ApkDownloader`:

1. Streams the selected asset to the app's private cache directory
   (`path_provider`'s `getTemporaryDirectory()`), reporting
   `(receivedBytes, totalBytes)` via a progress callback as chunks
   arrive.
2. Rejects (deletes the partial file, throws `ApkDownloadException`) if
   the final byte count doesn't exactly match the release asset's own
   declared `size` - catches a truncated/corrupted transfer.
3. If the release additionally publishes a `<asset-name>.sha256` file
   (plain-text `sha256sum`-style output; the release process below
   always publishes one), verifies the downloaded file's SHA-256
   against it, using `package:crypto` (pure-Dart, no native footprint).
   A mismatch deletes the file and throws.

`lib/features/update/widgets/update_download_dialog.dart` shows this as
a progress dialog; any `ApkDownloadException` (or an installer-handoff
failure) shows a plain error with **Retry** and **Cancel** - never a
silent failure, never a crash. The dialog is not barrier-dismissible
while a download is in flight, so a user can't accidentally lose the
in-progress state by tapping outside it.

## Installer hand-off (C3, C5)

`lib/services/update/apk_installer.dart` calls a small platform channel
(`trainyatri.app/apk_installer`) instead of a plugin - see the
`path_provider` comment in `pubspec.yaml` for why (a plugin commonly
used for "open this file", `open_filex`, currently pulls in a
`jni`/`objective_c` dependency chain for Android that isn't worth the
footprint against the 55 MB budget for a single intent call).
`android/app/src/main/kotlin/.../MainActivity.kt`'s `installApk`
handler:

1. Wraps the downloaded file in a `content://` URI via `FileProvider`
   (`android/app/src/main/res/xml/file_paths.xml` exposes only the
   app's own cache directory - nothing else on the device).
2. Starts `Intent(ACTION_VIEW)` with MIME type
   `application/vnd.android.package-archive`.

That's it - Android's own `PackageInstaller` UI takes over from there,
including prompting the user to enable "install unknown apps" for
Train Yatri the first time, if not already granted. This app never
calls any silent-install API and never could without a much deeper
Android permission (`INSTALL_PACKAGES`, system-app only) it doesn't
have or want.

## Session behavior (C1, C2, C6)

- The check (`updateCheckProvider`, a Riverpod `FutureProvider`) runs
  in the background from `HomeScreen.build`'s `ref.listen` - Home's own
  first frame never waits on it.
- The update-available dialog is shown **at most once per app
  session** (`updateDialogShownProvider`, in-memory only - a fresh
  launch is a fresh session).
- Offline or any check failure degrades to exactly the same behavior as
  "already up to date": nothing visible happens, no error, no crash.

## Manual check: Profile (C8)

`lib/features/profile/profile_screen.dart` is a deliberately minimal
screen - Block 4's requirement only (current version, update status, a
"Check for updates" button) - not the full Profile/Settings feature,
which remains a later block's scope (see the bottom nav's own code
comment). A manual check here distinguishes "you're on the latest
version" from "could not check for updates" (`UpdateChecker.checkDetailed`),
unlike the silent background check, which deliberately collapses both
to "do nothing" since a user who never asked shouldn't be told either
way.

## Force-update foundation (C7)

`lib/core/update/update_policy.dart`'s `UpdatePolicy` has a
`minimumSupportedVersion` field for a future block to wire up a real
source for (e.g. fetched alongside the release check, or from a remote
config service) and use to show a non-dismissible mandatory-update
prompt. **Nothing in Block 4 reads or enforces this field** -
`UpdatePolicy.none` (the only instance used) always evaluates
`isBelowMinimum` to `false`. This exists purely so that future logic
has a typed place to plug into without the update-check plumbing
itself needing to change shape.

## Release naming convention (v0.5.0+)

Every release publishes exactly:

```
train-yatri-vX.Y.Z.apk
train-yatri-vX.Y.Z.apk.sha256
```

and nothing else - no per-ABI variants, no debug build, no iOS
artifact. `ApkAssetSelector` matches the exact universal-APK filename
pattern; anything else (a `.sha256` file, a stray legacy per-ABI asset,
a source archive) is ignored.

Locally, multiple ABI-specific APKs may still be *built* when useful
for testing (`flutter build apk --release --split-per-abi`), but only
the universal build is ever uploaded to a release, and local build
output is cleaned up after verification - see "Local build artifacts"
below.

## Testing

- `test/core/update/`: pure-Dart unit tests (semantic version parsing/
  comparison, universal-APK asset selection, the full
  check/checkDetailed decision table via a fake `ReleaseSource`, and
  `ApkDownloader` against a real local `HttpServer` - progress, size
  mismatch, non-200, checksum match/mismatch).
- `test/features/update/update_download_dialog_test.dart`: the
  dialog's downloading/progress/error/retry/cancel/barrier-block states,
  using an injected fake `ApkDownloader`/`ApkInstaller` -
  `flutter_test`'s `TestWidgetsFlutterBinding` makes every real
  `HttpClient` created inside a `testWidgets` test return HTTP 400
  unconditionally, so a genuine network download cannot be exercised
  through a widget test at all (confirmed while developing this block;
  see that file's header comment).
- `test/features/home/home_screen_update_test.dart`: the dialog
  appears/doesn't appear correctly (update available / already current
  / check failed), "Later" dismisses without downloading, "Update now"
  opens the download dialog.
- `test/features/profile/profile_screen_test.dart`: the manual check's
  three outcomes, plus no-overflow at 320/360/390/412dp.

## `pubspec.yaml`'s `version:` must actually be bumped every release

The update check's "installed version" comes from `package_info_plus`,
which reads the real installed APK's `versionName` - Android derives
that from `pubspec.yaml`'s own `version:` field at build time
(`flutter.versionName`). **Discovered while building this block:**
`pubspec.yaml` had stayed at `0.2.0+2` through the v0.3.0 release (its
own git tag/GitHub Release bumped; the pubspec field silently didn't) -
had that shipped, a v0.3.0 install would have reported itself as
`0.2.0` to this very update check, permanently seeing every future
release as "already installed" and never offering an update at all.
Bumped to `0.4.0+4` for this release; **every future release must bump
this field to match its own tag**, or the whole update system silently
stops working for whoever installed the mismatched version.

## Local build artifacts

Only the current block's build output is kept on disk
(`build/app/outputs/flutter-apk/`, `release_staging/`) - older blocks'
local APKs and intermediate per-ABI builds are deleted once a release
is verified and published. This is purely a local-disk hygiene rule;
**GitHub Releases themselves are the permanent archive and are never
touched** - every prior release's assets (including v0.1.0-v0.4.0's
per-ABI APKs) remain exactly as published.

## Known limitations

- The release APK is signed with the debug keystore (see
  `android/app/build.gradle.kts`'s own `TODO` - unchanged from Block 1;
  a real release signing key is out of this block's scope to
  introduce unilaterally). This means installing an update over an
  existing install only works as long as every release keeps using the
  *same* debug keystore file - if that keystore is ever regenerated or
  built from a different machine's default keystore, Android will
  refuse the update as a signature mismatch (a fresh install would
  still work). A production release signing key is a real prerequisite
  before shipping this update mechanism to real users at scale.
- GitHub's unauthenticated REST API is rate-limited to 60 requests/hour
  per IP. This project's check runs at most once per app session, which
  is comfortably under that limit for normal use.
