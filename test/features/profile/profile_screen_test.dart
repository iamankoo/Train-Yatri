import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/core/update/github_release.dart';
import 'package:train_yatri/core/update/release_source.dart';
import 'package:train_yatri/data/providers/update_providers.dart';
import 'package:train_yatri/features/profile/profile_screen.dart';

class _FakeReleaseSource implements ReleaseSource {
  _FakeReleaseSource(this.release);
  final GitHubRelease? release;

  @override
  Future<GitHubRelease?> getLatestRelease() async => release;
}

Widget _wrap({required String installedVersion, GitHubRelease? release}) {
  return ProviderScope(
    overrides: [
      installedVersionProvider.overrideWith((ref) async => installedVersion),
      releaseSourceProvider.overrideWithValue(_FakeReleaseSource(release)),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  );
}

void main() {
  testWidgets('shows the installed app version', (tester) async {
    await tester.pumpWidget(_wrap(installedVersion: '0.4.0'));
    await tester.pumpAndSettle();

    expect(find.text('0.4.0'), findsOneWidget);
    expect(find.text('Update status not checked yet.'), findsOneWidget);
  });

  testWidgets(
    'Check for updates reports "latest version" when there is no newer '
    'release',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          installedVersion: '0.4.0',
          release: const GitHubRelease(
            tagName: 'v0.4.0',
            htmlUrl: '',
            assets: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('You\'re on the latest version.'), findsOneWidget);
      expect(find.text('Update now'), findsNothing);
    },
  );

  testWidgets(
    'Check for updates reports the newer version and offers Update now',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          installedVersion: '0.3.0',
          release: const GitHubRelease(
            tagName: 'v0.4.0',
            htmlUrl: '',
            assets: [
              ReleaseAsset(
                name: 'train-yatri-v0.4.0.apk',
                downloadUrl: 'https://example.com/apk',
                sizeBytes: 1000,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('Version 0.4.0 is available.'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    },
  );

  testWidgets(
    'Check for updates reports a failure honestly when the check cannot '
    'complete (offline, C6) - never silently pretends to be up to date',
    (tester) async {
      await tester.pumpWidget(
        _wrap(installedVersion: '0.4.0'),
      ); // release: null

      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not check for updates'),
        findsOneWidget,
      );
      expect(find.text('You\'re on the latest version.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the back button returns to the caller', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installedVersionProvider.overrideWith((ref) async => '0.4.0'),
          releaseSourceProvider.overrideWithValue(_FakeReleaseSource(null)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  child: const Text('open profile'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsNothing);
  });

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets('lays out without horizontal overflow at ${width}dp width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(installedVersion: '0.4.0'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
