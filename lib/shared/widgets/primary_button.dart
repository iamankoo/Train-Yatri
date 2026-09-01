import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// The single full-width, large-touch-target CTA button style used across
/// the app ("Search Trains" today; booking/tracking actions later).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: AppTextStyles.button,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final child = icon == null
        ? labelText
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTextStyles.button.color, size: 20),
              const SizedBox(width: 10),
              Flexible(child: labelText),
            ],
          );

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(onPressed: onPressed, child: child),
    );
  }
}
