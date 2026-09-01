import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The single elevated-white-rounded-card shell used across the app
/// (journey search, and later train/station result cards, ratings
/// forms, journey detail panels) so every card shares the same corner
/// radius, padding and shadow instead of each screen reinventing it.
class TrainYatriCard extends StatelessWidget {
  const TrainYatriCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: padding, child: child),
    );
  }
}
