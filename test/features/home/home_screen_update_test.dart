// Block 4's C1/C2: the silent background update check surfacing as a
// dialog on Home, at most once per session - kept in its own file so
// the pre-existing home_screen_test.dart doesn't need to know about the
// update system at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:train_yatri/core/update/github_release.dart';
import 'package:train_yatri/core/update/release_source.dart';
import 'package:train_yatri/data/providers/update_providers.dart';
import 'package:train_yatri/features/home/home_screen.dart';

import '../../test_support/fake_railway_repository.dart';

class _FakeReleaseSource implements ReleaseSource {
  _FakeReleaseSource(this.release);
  final GitHubRelease? release;

  @override
  Future<GitHubRelease?> getLatestRelease() async => release;
}

const _updateRelease = GitHubRelease(
  tagName: 'v9.9.9',
  htmlUrl: 'https://github.com/iamankoo/Train-Yatri/releases/tag/v9.9.9',
  assets: [
    ReleaseAsset(
      name: 'train-yatri-v9.9.9.apk',
      downloadUrl: 'https://example.com/train-yatri-v9.9.9.apk',
      sizeBytes: 1000,
    ),
  ],
);

Widget _wrap(Widget child, {GitHubRelease? release}) {
  return ProviderScope(
    overrides: [
      fakeRailwayRepositoryOverride(),
      installedVersionProvider.overrideWith((ref) async => '0.3.0'),
      releaseSourceProvider.overrideWithValue(_FakeReleaseSource(release)),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the update-available dialog when a newer release exists', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const HomeScreen(), release: _updateRelease));
    await tester.pumpAndSettle();

    expect(find.text('Train Yatri update available'), findsOneWidget);
    expect(find.textContaining('9.9.9'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('shows no dialog at all when already on the latest version', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const HomeScreen(),
        release: const GitHubRelease(
          tagName: 'v0.3.0',
          htmlUrl: '',
          assets: [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Train Yatri update available'), findsNothing);
  });

  testWidgets('shows no dialog and does not crash Home when the release check '
      'fails (offline, C6)', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen())); // release: null
    await tester.pumpAndSettle();

    expect(find.text('Train Yatri update available'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Later" dismisses the dialog without starting a download', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const HomeScreen(), release: _updateRelease));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Train Yatri update available'), findsNothing);
    expect(find.text('Downloading update'), findsNothing);
  });

  testWidgets(
    '"Update now" opens the download dialog (the download/install flow '
    'itself is covered in detail in '
    'test/features/update/update_download_dialog_test.dart, using an '
    'injected fake downloader - flutter_test makes every real '
    'HttpClient in a widget test return HTTP 400 unconditionally, so a '
    'genuine network download cannot be exercised through Home)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const HomeScreen(), release: _updateRelease),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update now'));
      await tester.pump();

      expect(find.text('Downloading update'), findsOneWidget);
    },
  );
}
