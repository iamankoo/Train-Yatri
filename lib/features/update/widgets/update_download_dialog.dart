import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/update/apk_downloader.dart';
import '../../../core/update/github_release.dart';
import '../../../core/update/update_info.dart';
import '../../../services/update/apk_installer.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';

enum _Phase { downloading, error }

/// C3's download/progress/retry UI, shown after the user taps "Update
/// now". Downloads [UpdateInfo.asset] with progress, validates it (see
/// [ApkDownloader]), and on success hands off to Android's installer
/// via [ApkInstaller] - never installs anything itself. A failure (bad
/// network, size/checksum mismatch) shows a plain error with Retry, per
/// C3/C6 - it never silently gives up or crashes.
///
/// Not shown as a standalone route: pushes it as a
/// non-dismissible-while-downloading dialog and returns once the
/// installer hand-off has been requested (or the user cancels).
///
/// [downloader]/[installer]/[targetDirectory] are overridable purely
/// for tests (see test/features/update/update_download_dialog_test.dart)
/// - `flutter_test`'s `TestWidgetsFlutterBinding` makes every real
/// `HttpClient` return HTTP 400 unconditionally, so a widget test
/// cannot exercise a genuine network download at all; substituting a
/// fake [ApkDownloader] here is what actually makes this dialog's
/// downloading/error/retry states testable. The real app never passes
/// any of these.
Future<void> startUpdateDownloadFlow(
  BuildContext context,
  UpdateInfo updateInfo, {
  ApkDownloader downloader = const ApkDownloader(),
  ApkInstaller installer = const ApkInstaller(),
  Directory? targetDirectory,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDownloadDialog(
      updateInfo: updateInfo,
      downloader: downloader,
      installer: installer,
      targetDirectory: targetDirectory,
    ),
  );
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({
    required this.updateInfo,
    required this.downloader,
    required this.installer,
    this.targetDirectory,
  });

  final UpdateInfo updateInfo;
  final ApkDownloader downloader;
  final ApkInstaller installer;
  final Directory? targetDirectory;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  _Phase _phase = _Phase.downloading;
  int _received = 0;
  int _total = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = widget.updateInfo.asset.sizeBytes;
      _errorMessage = null;
    });

    try {
      final checksumAssets = widget.updateInfo.release.assets
          .where((ReleaseAsset a) => a.name.endsWith('.sha256'))
          .toList();
      final targetDirectory =
          widget.targetDirectory ?? await getTemporaryDirectory();

      final file = await widget.downloader.download(
        asset: widget.updateInfo.asset,
        targetDirectory: targetDirectory,
        checksumAssets: checksumAssets,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );

      await widget.installer.install(file);
      if (mounted) Navigator.of(context).pop();
    } on ApkDownloadException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Could not start the installer: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Downloading update'),
      content: _phase == _Phase.downloading
          ? _DownloadingContent(received: _received, total: _total)
          : _ErrorContent(message: _errorMessage ?? 'Download failed.'),
      actions: [
        if (_phase == _Phase.error) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _startDownload, child: const Text('Retry')),
        ],
      ],
    );
  }
}

class _DownloadingContent extends StatelessWidget {
  const _DownloadingContent({required this.received, required this.total});

  final int received;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? received / total : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: progress, color: AppColors.primary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          total > 0
              ? '${_formatMb(received)} / ${_formatMb(total)} MB'
              : 'Starting download...',
          style: AppTextStyles.bodyMuted,
        ),
      ],
    );
  }

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message, style: AppTextStyles.body)),
      ],
    );
  }
}
