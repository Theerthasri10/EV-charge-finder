import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'nearby_stations_screen.dart';
import 'trip_planner_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void _goTo(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const NearbyStationsScreen(),
      const TripPlannerScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  selected: _currentIndex == 0,
                  onTap: () => _goTo(0),
                ),

                _NavItem(
                  icon: Icons.location_on_outlined,
                  activeIcon: Icons.location_on,
                  label: 'Nearby',
                  selected: _currentIndex == 1,
                  onTap: () => _goTo(1),
                ),

                _NavItem(
                  icon: Icons.alt_route_outlined,
                  activeIcon: Icons.alt_route,
                  label: 'Trip',
                  selected: _currentIndex == 2,
                  onTap: () => _goTo(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
    selected ? AppColors.primary : AppColors.textMuted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : icon,
              color: color,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.body(
                size: 10,
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}