import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_check_result.dart';
import '../../core/update/update_checker.dart';
import '../../data/providers/update_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/widgets/train_yatri_card.dart';
import '../update/widgets/update_download_dialog.dart';

/// A deliberately minimal Profile/Settings surface - Block 4's C8
/// requirement only ("Check for updates", current version, update
/// status), not the full Profile feature the bottom nav's own comment
/// documents as a later block's scope. Nothing else lives here yet.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

enum _CheckState { idle, checking, done }

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _CheckState _state = _CheckState.idle;
  UpdateCheckResult? _result;

  Future<void> _checkForUpdates() async {
    setState(() {
      _state = _CheckState.checking;
      _result = null;
    });

    final installedVersion = await ref.read(installedVersionProvider.future);
    final releaseSource = ref.read(releaseSourceProvider);
    final result = await UpdateChecker.checkDetailed(
      installedVersion: installedVersion,
      releaseSource: releaseSource,
    );

    if (!mounted) return;
    setState(() {
      _state = _CheckState.done;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final installedVersionAsync = ref.watch(installedVersionProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  TrainYatriCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('App version', style: AppTextStyles.label),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          installedVersionAsync.when(
                            data: (version) => version,
                            loading: () => '...',
                            error: (_, _) => 'Unknown',
                          ),
                          style: AppTextStyles.title,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.md),
                        _UpdateStatusRow(state: _state, result: _result),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _state == _CheckState.checking
                                ? null
                                : _checkForUpdates,
                            child: Text(
                              _state == _CheckState.checking
                                  ? 'Checking...'
                                  : 'Check for updates',
                            ),
                          ),
                        ),
                        if (_state == _CheckState.done &&
                            _result?.status ==
                                UpdateCheckStatus.updateAvailable) ...[
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => startUpdateDownloadFlow(
                                context,
                                _result!.updateInfo!,
                              ),
                              child: const Text('Update now'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateStatusRow extends StatelessWidget {
  const _UpdateStatusRow({required this.state, required this.result});

  final _CheckState state;
  final UpdateCheckResult? result;

  @override
  Widget build(BuildContext context) {
    if (state == _CheckState.idle) {
      return const Text(
        'Update status not checked yet.',
        style: AppTextStyles.bodyMuted,
      );
    }
    if (state == _CheckState.checking) {
      return const Text(
        'Checking for updates...',
        style: AppTextStyles.bodyMuted,
      );
    }

    final r = result!;
    final (message, color) = switch (r.status) {
      UpdateCheckStatus.upToDate => (
        'You\'re on the latest version.',
        AppColors.success,
      ),
      UpdateCheckStatus.updateAvailable => (
        'Version ${r.updateInfo!.latestVersion} is available.',
        AppColors.warning,
      ),
      UpdateCheckStatus.checkFailed => (
        'Could not check for updates. Check your connection and try again.',
        AppColors.textSecondary,
      ),
    };
    return Text(message, style: AppTextStyles.body.copyWith(color: color));
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          const Text('Profile', style: AppTextStyles.title),
        ],
      ),
    );
  }
}
