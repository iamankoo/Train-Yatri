import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_routes.dart';
import '../../data/providers/railway_providers.dart';
import '../../shared/theme/app_colors.dart';

/// The Dart-side splash screen.
///
/// A native splash (configured via `flutter_native_splash`, see
/// pubspec.yaml) is already visible the instant the app process starts,
/// using the same background color and brand mark - that avoids any
/// blank/white frame while the Flutter engine spins up. The moment this
/// widget's first frame is drawn, it takes over showing the full
/// `assets/splashscreen.png` artwork for the remaining hold time, then
/// fades into Home. `BoxFit.contain` is used deliberately (not `cover`)
/// so the artwork is never cropped or distorted on any aspect ratio -
/// on a device whose screen is a different shape than the artwork, the
/// matching gradient background shows at the edges instead of cutting
/// any of the composition off.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const Duration holdDuration = Duration(seconds: 3);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.96,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    // Fire-and-forget: opens (and copies, on first launch) the railway
    // database during the splash hold so Home/search rarely has to wait
    // for it later. Riverpod caches the resulting future regardless of
    // whether anything is watching it yet.
    ref.read(railwayRepositoryProvider);

    Future.delayed(SplashScreen.holdDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashGradientBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.splashGradientTop,
              AppColors.splashGradientBottom,
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: SizedBox.expand(
              child: Image.asset(
                'assets/splashscreen.png',
                fit: BoxFit.contain,
                alignment: Alignment.center,
                semanticLabel: 'Train Yatri',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
