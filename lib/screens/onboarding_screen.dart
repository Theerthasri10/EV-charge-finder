import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _totalPages = 3;
  static const _onboardingSeenKey = 'has_seen_onboarding';

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onNextPressed() {
    if (_currentPage < _totalPages - 1) {
      _goToPage(_currentPage + 1);
    } else {
      _finishOnboarding();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _totalPages - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // ================= SKIP BUTTON =================
            Positioned(
              top: 4,
              right: 16,
              child: AnimatedOpacity(
                opacity: isLastPage ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: TextButton(
                  onPressed: isLastPage ? null : () => _goToPage(_totalPages - 1),
                  child: Text('Skip', style: AppTextStyles.body(size: 13, weight: FontWeight.w600, color: AppColors.textMuted)),
                ),
              ),
            ),

            // ================= SLIDES =================
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    children: const [
                      _OnboardSlide(
                        illustration: _RadarIllustration(),
                        title: 'Find Nearby Chargers Instantly',
                        description:
                        'We first search nearby and automatically expand the search radius until we find the best charging stations for you.',
                      ),
                      _OnboardSlide(
                        illustration: _RouteIllustration(),
                        title: 'Plan Every Journey with Confidence',
                        description:
                        'Enter your destination to view charging stations along your route and enjoy worry-free travel.',
                      ),
                      _OnboardSlide(
                        illustration: _TapRevealIllustration(),
                        title: 'Everything You Need Before You Charge',
                        description:
                        'View connector types, charging power, and station details — all in one place.',
                      ),
                    ],
                  ),
                ),

                // ================= DOTS + CTA =================
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_totalPages, (index) {
                          final active = index == _currentPage;
                          return GestureDetector(
                            onTap: () => _goToPage(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 3.5),
                              width: active ? 22 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: active ? AppColors.primary : AppColors.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _onNextPressed,
                          child: Text(isLastPage ? 'Get Started' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared layout for one onboarding slide: illustration on top, text below.
class _OnboardSlide extends StatelessWidget {
  final Widget illustration;
  final String title;
  final String description;

  const _OnboardSlide({required this.illustration, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          Expanded(child: Center(child: illustration)),
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.display(size: 21, weight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTextStyles.body(size: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ================= SLIDE 1: RADAR ANIMATION =================
class _RadarIllustration extends StatefulWidget {
  const _RadarIllustration();

  @override
  State<_RadarIllustration> createState() => _RadarIllustrationState();
}

class _RadarIllustrationState extends State<_RadarIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _RadarRing(controller: _controller, delayFraction: 0.0),
          _RadarRing(controller: _controller, delayFraction: 0.25),
          _RadarRing(controller: _controller, delayFraction: 0.5),

          // Center pin
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card,
              border: Border.all(color: AppColors.primary, width: 3),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 26, offset: const Offset(0, 12))],
            ),
            child: const Icon(Icons.location_on, color: AppColors.primary, size: 28),
          ),

          // Mini station pins, appearing/disappearing
          Positioned(top: 20, left: 8, child: _MiniPin(controller: _controller, delayFraction: 0.1)),
          Positioned(top: 140, right: 12, child: _MiniPin(controller: _controller, delayFraction: 0.4)),
          Positioned(bottom: 18, left: 34, child: _MiniPin(controller: _controller, delayFraction: 0.7)),
        ],
      ),
    );
  }
}

class _RadarRing extends StatelessWidget {
  final AnimationController controller;
  final double delayFraction;
  const _RadarRing({required this.controller, required this.delayFraction});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        final size = 60 + (140 * t);
        final opacity = (1 - t) * 0.7;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: opacity.clamp(0.0, 1.0)), width: 2),
          ),
        );
      },
    );
  }
}

class _MiniPin extends StatelessWidget {
  final AnimationController controller;
  final double delayFraction;
  const _MiniPin({required this.controller, required this.delayFraction});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + delayFraction) % 1.0;
        final pulse = (t < 0.5) ? (t / 0.5) : (1 - (t - 0.5) / 0.5);
        final scale = 0.6 + (0.4 * pulse);
        final opacity = 0.4 + (0.6 * pulse);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.card,
                border: Border.all(color: AppColors.secondary, width: 2),
              ),
              child: const Icon(Icons.bolt, color: AppColors.secondary, size: 13),
            ),
          ),
        );
      },
    );
  }
}

// ================= SLIDE 2: ROUTE DRAWING ANIMATION =================
class _RouteIllustration extends StatefulWidget {
  const _RouteIllustration();

  @override
  State<_RouteIllustration> createState() => _RouteIllustrationState();
}

class _RouteIllustrationState extends State<_RouteIllustration> with TickerProviderStateMixin  {
  late final AnimationController _dashController;
  late final AnimationController _carController;

  static final List<Offset> _routePoints = [
    const Offset(40, 180),
    const Offset(90, 130),
    const Offset(130, 90),
    const Offset(220, 30),
  ];

  @override
  void initState() {
    super.initState();
    _dashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();
    _carController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  }

  @override
  void dispose() {
    _dashController.dispose();
    _carController.dispose();
    super.dispose();
  }

  Offset _pointOnPath(double t) {
    // Simple piecewise-linear interpolation across the route points.
    final segmentCount = _routePoints.length - 1;
    final scaled = t * segmentCount;
    final index = scaled.floor().clamp(0, segmentCount - 1);
    final localT = scaled - index;
    return Offset.lerp(_routePoints[index], _routePoints[index + 1], localT)!;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 220,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(260, 220),
            painter: _RoutePainter(points: _routePoints, dashOffset: _dashController),
          ),
          // Start marker (home)
          Positioned(
            left: _routePoints.first.dx - 16,
            top: _routePoints.first.dy - 16,
            child: _RouteEndpoint(icon: Icons.home, color: AppColors.secondary),
          ),
          // End marker (charger)
          Positioned(
            left: _routePoints.last.dx - 16,
            top: _routePoints.last.dy - 16,
            child: _RouteEndpoint(icon: Icons.bolt, color: AppColors.primary),
          ),
          // Moving car icon
          AnimatedBuilder(
            animation: _carController,
            builder: (context, child) {
              final pos = _pointOnPath(_carController.value);
              return Positioned(
                left: pos.dx - 12,
                top: pos.dy - 12,
                child: const Icon(Icons.directions_car, color: AppColors.text, size: 24),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Offset> points;
  final Animation<double> dashOffset;

  _RoutePainter({required this.points, required this.dashOffset}) : super(repaint: dashOffset);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.secondary
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Manually draw dashes along the path, shifting the phase for a "marching ants" effect.
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      const dashLength = 6.0;
      const gapLength = 8.0;
      double distance = -dashOffset.value * (dashLength + gapLength);
      while (distance < metric.length) {
        final start = distance.clamp(0.0, metric.length);
        final end = (distance + dashLength).clamp(0.0, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) => true;
}

class _RouteEndpoint extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _RouteEndpoint({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.card,
        border: Border.all(color: color, width: 3),
      ),
      child: Icon(icon, color: color, size: 15),
    );
  }
}

// ================= SLIDE 3: TAP-TO-REVEAL ANIMATION =================
class _TapRevealIllustration extends StatefulWidget {
  const _TapRevealIllustration();

  @override
  State<_TapRevealIllustration> createState() => _TapRevealIllustrationState();
}

class _TapRevealIllustrationState extends State<_TapRevealIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 230,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;

          // Glow pulse
          final glowScale = 0.9 + (0.18 * (0.5 - (t - 0.5).abs()) * 2);

          // Tap hand: visible roughly 18%-46% of the cycle
          final handVisible = t >= 0.18 && t <= 0.46;
          final handProgress = handVisible ? ((t - 0.18) / 0.28).clamp(0.0, 1.0) : 0.0;

          // Detail chip: visible roughly 40%-88% of the cycle
          final chipVisible = t >= 0.40 && t <= 0.88;
          final chipT = chipVisible
              ? (t < 0.55 ? ((t - 0.40) / 0.15).clamp(0.0, 1.0) : 1.0)
              : 0.0;
          final chipFadeOut = t > 0.88 ? 0.0 : 1.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: glowScale,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [AppColors.primary.withValues(alpha: 0.22), AppColors.primary.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 50,
                child: Icon(Icons.bolt, color: AppColors.primary, size: 58),
              ),
              if (handVisible)
                Positioned(
                  top: 64 - (handProgress * 6),
                  right: 44,
                  child: Opacity(
                    opacity: handProgress,
                    child: const Icon(Icons.touch_app, color: AppColors.text, size: 28),
                  ),
                ),
              if (chipVisible)
                Positioned(
                  bottom: 6,
                  child: Opacity(
                    opacity: chipT * chipFadeOut,
                    child: Transform.translate(
                      offset: Offset(0, (1 - chipT) * 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _chipPart(Icons.ev_station, 'CCS2'),
                            _chipSeparator(),
                            _chipPart(Icons.bolt, '50kW'),
                            _chipSeparator(),
                            _chipPart(Icons.check_circle, 'Available'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _chipPart(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.text),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.body(size: 11.5, weight: FontWeight.w700)),
      ],
    );
  }

  Widget _chipSeparator() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text('·', style: AppTextStyles.body(size: 12, color: AppColors.border)),
  );
}