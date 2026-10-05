import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'nearby_stations_screen.dart';
import 'trip_planner_screen.dart';

class HomeTab extends StatelessWidget {
  final VoidCallback onGoToNearby;
  final VoidCallback onGoToTrip;

  const HomeTab({super.key, required this.onGoToNearby, required this.onGoToTrip});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back 👋', style: AppTextStyles.body(size: 13, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text('Where are we charging today?', style: AppTextStyles.display(size: 20, weight: FontWeight.w800)),

              const SizedBox(height: 24),

              _ActionCard(
                icon: Icons.near_me,
                iconColor: AppColors.primary,
                title: 'Nearby Stations',
                subtitle: 'Find charging points close to you right now',
                onTap: onGoToNearby,
              ),
              const SizedBox(height: 14),
              _ActionCard(
                icon: Icons.alt_route,
                iconColor: AppColors.secondary,
                title: 'Plan a Trip',
                subtitle: 'Map a route and find stations along the way',
                onTap: onGoToTrip,
              ),

              const SizedBox(height: 28),

              Text('Tamil Nadu Coverage', style: AppTextStyles.display(size: 14, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: const [
                    _StatBlock(value: '881+', label: 'Stations'),
                    _StatBlock(value: '32', label: 'Districts'),
                    _StatBlock(value: '24/7', label: 'Live Data'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.display(size: 14.5, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;
  const _StatBlock({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTextStyles.display(size: 17, weight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 3),
          Text(label, style: AppTextStyles.body(size: 10.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}