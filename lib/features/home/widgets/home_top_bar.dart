import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/coming_soon.dart';

/// Menu + notifications row at the very top of Home. Neither destination
/// (a drawer, a notifications screen) exists yet, so both give honest
/// "coming soon" feedback instead of opening an empty placeholder.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => showComingSoon(context, 'Menu'),
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Menu',
        ),
        IconButton(
          onPressed: () => showComingSoon(context, 'Notifications'),
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textPrimary,
          ),
          tooltip: 'Notifications',
        ),
      ],
    );
  }
}
