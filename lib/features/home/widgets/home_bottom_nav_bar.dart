import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/coming_soon.dart';
import '../../live_tracking/live_tab_screen.dart';
import '../../profile/profile_screen.dart';

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Bottom navigation shell.
///
/// "Home" is a real, built destination since Block 1. "Live" now opens
/// the real Live Status feature (Block 6). Journeys (Block 3/9) remains
/// a planned feature area and is presented as visibly *inactive* -
/// tapping it gives honest "coming soon" feedback rather than
/// navigating to an empty screen or implying functionality that isn't
/// there yet. "Profile" now opens a deliberately minimal screen (Block
/// 4, C8: only the update-check surface) - the full Profile feature
/// itself is still Block 8/9's scope.
class HomeBottomNavBar extends StatelessWidget {
  const HomeBottomNavBar({super.key});

  static const _items = [
    _NavItem('Home', Icons.home_rounded),
    _NavItem('Live', Icons.train_rounded),
    _NavItem('Journeys', Icons.confirmation_number_outlined),
    _NavItem('Profile', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in _items)
                Expanded(
                  child: _NavButton(
                    item: item,
                    selected: item == _items.first,
                    onTap: item == _items.first
                        ? null
                        : item.label == 'Profile'
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          )
                        : item.label == 'Live'
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LiveTabScreen(),
                            ),
                          )
                        : () => showComingSoon(context, item.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '${item.label}, selected' : item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppTextStyles.navLabel.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
