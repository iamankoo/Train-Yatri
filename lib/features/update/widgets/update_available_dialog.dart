import 'package:flutter/material.dart';

import '../../../core/update/update_info.dart';

/// C2's update prompt: "Train Yatri update available" / "Version X.X.X
/// is available." with "Update now" / "Later". Returns `true` if the
/// user chose to update, `false`/`null` for "Later" or a dismissal -
/// callers never re-show this automatically within the same session
/// either way (see `updateDialogShownProvider`).
Future<bool?> showUpdateAvailableDialog(
  BuildContext context,
  UpdateInfo updateInfo,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Train Yatri update available'),
      content: Text('Version ${updateInfo.latestVersion} is available.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Update now'),
        ),
      ],
    ),
  );
}
