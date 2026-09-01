import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The small rounded, tinted square behind an icon - used throughout the
/// Home screen (search rows, quick actions) to match the reference design.
class IconChip extends StatelessWidget {
  const IconChip({
    required this.icon,
    super.key,
    this.background = AppColors.iconChipBackground,
    this.foreground = AppColors.primary,
    this.size = 40,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: foreground, size: size * 0.5),
    );
  }
}
