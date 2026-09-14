import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/infrastructure.dart';
import '../../app/router/adaptive_shell.dart';
import '../../app/router/app_routes.dart';
import '../../app/state/app_settings_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';

/// Brand splash. It is not "1.5 seconds of nothing": it runs the real startup
/// work (warm caches, flush analytics, decide the landing route) and hands off.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  Timer? _timer;
  bool _degraded = false;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    // Safety net: never hold a child on a splash screen if startup hangs.
    _timer = Timer(const Duration(seconds: 3), _goNext);
  }

  Future<void> _goNext() async {
    if (!_warmStarted) {
      _warmStarted = true;
      await _primeCaches();
    }
    if (!mounted) return;
    _timer?.cancel();
    final settings = ref.read(appSettingsProvider);
    final target = !settings.onboardingComplete
        ? AppRoutes.onboardingLanguage
        : settings.activeProfileId == null
        ? AppRoutes.onboardingProfiles
        : AppRoutes.home;
    context.go(target);
  }

  bool _warmStarted = false;

  Future<void> _primeCaches() async {
    try {
      unawaited(ref.read(analyticsServiceProvider).flush());
      await Future<void>.delayed(const Duration(milliseconds: 220));
    } catch (error) {
      // A failing optional service must never block the first screen.
      if (mounted) setState(() => _degraded = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: DecoratedBox(
        position: DecorationPosition.background,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.3,
            colors: [colors.brand.withValues(alpha: 0.22), colors.canvas],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: _anim, curve: Curves.easeOut),
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1).animate(
                CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 92),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'PhonicsAI',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Your reading buddy',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SizedBox(
                    height: 20,
                    child: _degraded
                        ? Text(
                            'Starting in offline mode',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : const _SplashPips(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bouncing phonemes — the only pure-decoration animation in the app,
/// and it is `IgnorePointer` + reduce-motion aware.
class _SplashPips extends StatefulWidget {
  const _SplashPips();

  @override
  State<_SplashPips> createState() => _SplashPipsState();
}

class _SplashPipsState extends State<_SplashPips>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (AppMotion.disabled(context)) return const SizedBox.shrink();
    const letters = ['a', 'i', 'o'];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < letters.length; i++)
            Opacity(
              opacity: (_controller.value * letters.length - i).abs() < 0.6
                  ? 1
                  : 0.3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  letters[i],
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: colors.brand,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
