import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart'; // built in the next step
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _fadeUp;

  static const _onboardingSeenKey = 'has_seen_onboarding';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _logoScale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fadeUp = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();
    _decideNextScreen();
  }

  Future<void> _decideNextScreen() async {
    // Show the splash for a fixed, short duration — this is intentional,
    // not a loading spinner waiting on network calls.
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding =  false;

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => hasSeenOnboarding ? const MainShell() : const OnboardingScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFECFDF3)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- Pulsing rings + logo badge ----
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _PulsingRing(delay: Duration.zero),
                    _PulsingRing(delay: const Duration(milliseconds: 600)),
                    ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.primaryDark],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.55),
                              blurRadius: 36,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.bolt, color: Colors.white, size: 44),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ---- Brand text ----
              FadeTransition(
                opacity: _fadeUp,
                child: Column(
                  children: [
                    Text('EV Charge Finder', style: AppTextStyles.display(size: 23, weight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Real stations. Real time. Real Tamil Nadu.',
                      style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ---- Loading dots ----
              FadeTransition(
                opacity: _fadeUp,
                child: const _LoadingDots(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One expanding, fading ring — two of these staggered creates the "radar pulse" effect.
class _PulsingRing extends StatefulWidget {
  final Duration delay;
  const _PulsingRing({required this.delay});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    Future.delayed(widget.delay, () {
      if (mounted) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value; // 0.0 -> 1.0 repeating
        final size = 60 + (140 * t);
        final opacity = (1 - t).clamp(0.0, 1.0) * 0.7;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: opacity), width: 2),
          ),
        );
      },
    );
  }
}

/// Three blinking dots, staggered — a simple "still working" indicator.
class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = (_controller.value - (i * 0.15)) % 1.0;
            final scale = t < 0.4 ? 0.85 + (0.15 * (t / 0.4)) : 1.0 - (0.15 * ((t - 0.4) / 0.6));
            final opacity = t < 0.4 ? 0.25 + (0.75 * (t / 0.4)) : 1.0 - (0.75 * ((t - 0.4) / 0.6));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: opacity.clamp(0.0, 1.0)),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}