import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/ev_station.dart';

class StationDetailScreen extends StatefulWidget {
  final EvStation station;
  const StationDetailScreen({super.key, required this.station});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  int _selectedTab = 0; // 0 = Information, 1 = Connectors
  bool _isFavorite = false;

  Future<void> _openDirections() async {
    final station = widget.station;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${station.latitude},${station.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= HERO HEADER =================
            Stack(
              children: [
                Container(
                  height: 230,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F2E22), Color(0xFF123A28), Color(0xFF0B1220)],
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) => _ChargingStall(index: i)),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CircleIconButton(
                          icon: Icons.arrow_back,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        Row(
                          children: [
                            _CircleIconButton(
                              icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
                              onTap: () => setState(() => _isFavorite = !_isFavorite),
                            ),
                            const SizedBox(width: 8),
                            _CircleIconButton(icon: Icons.share, onTap: () {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ================= INFO CARD =================
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 28, offset: const Offset(0, 12)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(station.name, style: AppTextStyles.display(size: 18, weight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 15, color: AppColors.primary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            station.address,
                            style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    if (station.operatorName != null && station.operatorName!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.business, size: 15, color: AppColors.textMuted),
                          const SizedBox(width: 5),
                          Text('Operated by ${station.operatorName}', style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _StatPill(
                          value: '${station.kwhRating} kW',
                          label: 'MAX POWER',
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        _StatPill(
                          value: '${station.totalPorts}',
                          label: 'PORTS',
                          color: AppColors.secondary,
                        ),
                        const SizedBox(width: 10),
                        _StatPill(
                          value: station.connectorTypes,
                          label: 'CONNECTOR',
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ================= TABS =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _PillTab(label: 'Information', selected: _selectedTab == 0, onTap: () => setState(() => _selectedTab = 0)),
                  const SizedBox(width: 8),
                  _PillTab(label: 'Connectors', selected: _selectedTab == 1, onTap: () => setState(() => _selectedTab = 1)),
                ],
              ),
            ),

            // ================= TAB CONTENT =================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _selectedTab == 0
                  ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About', style: AppTextStyles.display(size: 13, weight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    '${station.name} is a verified EV charging station in Tamil Nadu offering ${station.totalPorts} charging port${station.totalPorts == 1 ? '' : 's'} with ${station.connectorTypes} connectivity, rated at ${station.kwhRating} kW.',
                    style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted, weight: FontWeight.w400),
                  ),
                ],
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connector Details', style: AppTextStyles.display(size: 13, weight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _InfoRow(label: 'Connector type', value: station.connectorTypes),
                  _InfoRow(label: 'Total ports', value: '${station.totalPorts}'),
                  _InfoRow(label: 'Power rating', value: '${station.kwhRating} kW'),
                ],
              ),
            ),

            const SizedBox(height: 100), // room above the floating footer
          ],
        ),
      ),

      // ================= FOOTER CTA =================
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openDirections,
              icon: const Icon(Icons.directions, color: Colors.white),
              label: const Text('Get Directions'),
            ),
          ),
        ),
      ),
    );
  }
}

// ================= SMALL REUSABLE WIDGETS =================

class _ChargingStall extends StatelessWidget {
  final int index;
  const _ChargingStall({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF134E2E),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.7), blurRadius: 10, spreadRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatPill({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.display(size: 13, weight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.body(size: 9, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.body(
            size: 12.5,
            weight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body(size: 12.5, color: AppColors.textMuted)),
          Text(value, style: AppTextStyles.body(size: 12.5, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}