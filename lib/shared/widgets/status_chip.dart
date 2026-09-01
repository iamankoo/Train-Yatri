import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Small status pill, established now as part of the design system for
/// the freshness/availability states later blocks need everywhere data
/// can be live, cached, stale or unavailable (live train status, PNR,
/// ratings, offline tracking). Never used to label anything simulated
/// as [StatusTone.live] - callers only reach for that tone once real
/// data actually backs it.
enum StatusTone { live, cached, stale, unavailable, neutral }

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.tone, super.key});

  final String label;
  final StatusTone tone;

  ({Color background, Color foreground}) get _colors {
    switch (tone) {
      case StatusTone.live:
        return (
          background: AppColors.success.withValues(alpha: 0.12),
          foreground: AppColors.success,
        );
      case StatusTone.cached:
        return (
          background: AppColors.primary.withValues(alpha: 0.12),
          foreground: AppColors.primary,
        );
      case StatusTone.stale:
        return (
          background: AppColors.warning.withValues(alpha: 0.14),
          foreground: AppColors.warning,
        );
      case StatusTone.unavailable:
        return (
          background: AppColors.error.withValues(alpha: 0.12),
          foreground: AppColors.error,
        );
      case StatusTone.neutral:
        return (
          background: AppColors.divider,
          foreground: AppColors.textSecondary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.foreground,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
