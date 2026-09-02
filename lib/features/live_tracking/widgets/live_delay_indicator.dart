import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';

/// A compact "late / on time / unknown" indicator - a small dot that
/// gently pulses (never the surrounding UI) plus a short label.
///
/// [delayMinutes] is the real, possibly-absent value from the backend:
/// `null` means the provider did not report a delay and renders a
/// neutral "Delay unknown" - it is never upgraded to "On time" (that
/// label only appears for an explicit, reported `0`).
class LiveDelayIndicator extends StatefulWidget {
  const LiveDelayIndicator({required this.delayMinutes, super.key});

  final int? delayMinutes;

  @override
  State<LiveDelayIndicator> createState() => _LiveDelayIndicatorState();
}

class _LiveDelayIndicatorState extends State<LiveDelayIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.35,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delay = widget.delayMinutes;
    final (color, label, blink) = switch (delay) {
      null => (AppColors.textSecondary, 'Delay unknown', false),
      <= 0 => (AppColors.success, 'On time', true),
      _ => (AppColors.error, '$delay min late', true),
    };

    // Reduced-motion: a real accessibility signal from the platform,
    // not a guess - the dot still communicates status by color alone,
    // just without the pulse.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          (blink && !reduceMotion)
              ? FadeTransition(opacity: _opacity, child: dot)
              : dot,
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
