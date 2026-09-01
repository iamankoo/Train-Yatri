import 'package:flutter/material.dart';

/// Block 1 ships the navigation shell and the Home screen layout only.
/// Every control whose real behaviour depends on a later block (station
/// search, live status, PNR, booking, ratings, other bottom-nav tabs)
/// routes through this instead of pretending to work or silently doing
/// nothing, so the UI never claims functionality that isn't there yet.
///
/// [detail] lets a caller be specific about when the feature lands (e.g.
/// "coming in the next block") instead of the generic "coming soon".
void showComingSoon(BuildContext context, String feature, [String? detail]) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$feature is ${detail ?? 'coming soon'}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}
