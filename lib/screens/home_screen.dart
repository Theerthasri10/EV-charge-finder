// lib/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_theme.dart';
import '../models/ev_station.dart';
import '../services/geocoding_service.dart';
import '../services/ev_station_service.dart';
import '../utils/geo_utils.dart';

import 'trip_planner_screen.dart';
import 'nearby_stations_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ================= SERVICES =================

  final _geocodingService = GeocodingService();
  final _stationService = EvStationService();

  // ================= SEARCH =================

  final TextEditingController _searchController =
  TextEditingController();

  List<PlaceSuggestion> _suggestions = [];
  bool _isSearching = false;
  Timer? _debounce;

  // ================= NEAREST STATION =================

  EvStation? _nearestStation;
  double? _nearestDistanceKm;

  bool _isLoadingNearest = true;
  String? _nearestError;

  // ================= INITIAL LOAD =================

  @override
  void initState() {
    super.initState();

    // Load nearest station when Home screen opens.
    _loadNearestStation();
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _goToTripPlanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TripPlannerScreen(),
      ),
    );
  }

  void _goToNearbyStations(
      BuildContext context, {
        String? initialQuery,
      }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NearbyStationsScreen(
          initialQuery: initialQuery,
        ),
      ),
    );
  }

  // ============================================================
  // SEARCH
  // ============================================================

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    _debounce = Timer(
      const Duration(milliseconds: 400),
          () async {
        if (query.trim().length < 3) {
          if (!mounted) return;

          setState(() {
            _suggestions = [];
            _isSearching = false;
          });

          return;
        }

        if (!mounted) return;

        setState(() {
          _isSearching = true;
        });

        try {
          final results =
          await _geocodingService.autocomplete(query);

          if (!mounted) return;

          setState(() {
            _suggestions = results;
            _isSearching = false;
          });
        } catch (_) {
          if (!mounted) return;

          setState(() {
            _suggestions = [];
            _isSearching = false;
          });
        }
      },
    );
  }

  void _selectSuggestion(
      PlaceSuggestion suggestion,
      ) {
    _searchController.text = suggestion.displayName;

    setState(() {
      _suggestions = [];
    });

    FocusScope.of(context).unfocus();

    _goToNearbyStations(
      context,
      initialQuery: suggestion.displayName,
    );
  }

  void _submitSearch() {
    final query = _searchController.text.trim();

    if (query.isEmpty) return;

    setState(() {
      _suggestions = [];
    });

    FocusScope.of(context).unfocus();

    _goToNearbyStations(
      context,
      initialQuery: query,
    );
  }

  // ============================================================
  // LOAD NEAREST STATION
  //
  // Uses the SAME GPS + backend approach as NearbyStationsScreen.
  // ============================================================

  Future<void> _loadNearestStation() async {
    if (!mounted) return;

    setState(() {
      _isLoadingNearest = true;
      _nearestError = null;
    });

    try {
      // --------------------------------------------------------
      // STEP 1: Check location service
      // --------------------------------------------------------

      print('HOME STEP 1: Checking location service...');

      final serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      print(
        'HOME STEP 1 DONE: serviceEnabled = $serviceEnabled',
      );

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          _isLoadingNearest = false;
          _nearestError =
          'Please turn on location services.';
        });

        return;
      }

      // --------------------------------------------------------
      // STEP 2: Check permission
      // --------------------------------------------------------

      print('HOME STEP 2: Checking permission...');

      LocationPermission permission =
      await Geolocator.checkPermission();

      print(
        'HOME STEP 2 DONE: permission = $permission',
      );

      if (permission == LocationPermission.denied) {
        print('HOME STEP 2b: Requesting permission...');

        permission =
        await Geolocator.requestPermission();

        print(
          'HOME STEP 2b DONE: permission = $permission',
        );

        if (permission == LocationPermission.denied) {
          if (!mounted) return;

          setState(() {
            _isLoadingNearest = false;
            _nearestError =
            'Location permission denied.';
          });

          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          _isLoadingNearest = false;
          _nearestError =
          'Location permission permanently denied.';
        });

        return;
      }

      // --------------------------------------------------------
      // STEP 3: Get current position
      // --------------------------------------------------------

      print('HOME STEP 3: Getting current position...');

      final position =
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 15),
      );

      print(
        'HOME STEP 3 DONE: '
            'lat=${position.latitude}, '
            'lng=${position.longitude}',
      );

      // --------------------------------------------------------
      // STEP 4: Fetch stations
      //
      // Same service used by NearbyStationsScreen.
      // --------------------------------------------------------

      print(
        'HOME STEP 4: Fetching stations from backend...',
      );

      final allStations =
      await _stationService.getAllStations();

      print(
        'HOME STEP 4 DONE: '
            'got ${allStations.length} stations',
      );

      if (allStations.isEmpty) {
        if (!mounted) return;

        setState(() {
          _isLoadingNearest = false;
          _nearestError =
          'No charging stations found.';
        });

        return;
      }

      // --------------------------------------------------------
      // STEP 5: Find closest station
      // --------------------------------------------------------

      print(
        'HOME STEP 5: Finding nearest station...',
      );

      EvStation? closestStation;
      double closestDistance = double.infinity;

      for (final station in allStations) {
        final distance = GeoUtils.distanceKm(
          position.latitude,
          position.longitude,
          station.latitude,
          station.longitude,
        );

        if (distance < closestDistance) {
          closestDistance = distance;
          closestStation = station;
        }
      }

      print(
        'HOME STEP 5 DONE: '
            'nearest=${closestStation?.name}, '
            'distance=$closestDistance km',
      );

      // --------------------------------------------------------
      // STEP 6: Update UI
      // --------------------------------------------------------

      if (!mounted) return;

      setState(() {
        _nearestStation = closestStation;
        _nearestDistanceKm = closestDistance;
        _isLoadingNearest = false;
        _nearestError = null;
      });
    } catch (e, stackTrace) {
      print('HOME ERROR: $e');
      print('HOME STACK TRACE: $stackTrace');

      if (!mounted) return;

      setState(() {
        _isLoadingNearest = false;
        _nearestError =
        'Could not load nearby station.';
      });
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24,
          ),

          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [

              // ==================================================
              // TOP BAR
              // ==================================================

              Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

                children: [

                  Text(
                    'Good morning, Theerthasri 👋',
                    style: AppTextStyles.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),

                  Container(
                    width: 38,
                    height: 38,

                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),

                    child: const Icon(
                      Icons.notifications_none_rounded,
                      size: 20,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ==================================================
              // HEADING
              // ==================================================

              Text(
                'Where do you want\nto charge today?',
                style: AppTextStyles.display(
                  size: 24,
                  weight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // SEARCH BAR
              // ==================================================

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),

                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius:
                  BorderRadius.circular(16),

                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),

                child: Row(
                  children: [

                    const Icon(
                      Icons.search_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: TextField(
                        controller: _searchController,

                        onChanged:
                        _onSearchChanged,

                        onSubmitted:
                            (_) => _submitSearch(),

                        style:
                        AppTextStyles.body(
                          size: 13.5,
                          weight: FontWeight.w600,
                        ),

                        decoration:
                        InputDecoration(
                          hintText:
                          'Search location or charging station',

                          hintStyle:
                          AppTextStyles.body(
                            size: 13.5,
                            color:
                            AppColors.textMuted,
                          ),

                          border:
                          InputBorder.none,

                          isDense: true,

                          contentPadding:
                          const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),

                    InkWell(
                      onTap: _submitSearch,

                      borderRadius:
                      BorderRadius.circular(20),

                      child: const Padding(
                        padding:
                        EdgeInsets.all(8),

                        child: Icon(
                          Icons.my_location_rounded,
                          color:
                          AppColors.primary,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ==================================================
              // SEARCH LOADING
              // ==================================================

              if (_isSearching)
                const Padding(
                  padding:
                  EdgeInsets.only(top: 10),

                  child:
                  LinearProgressIndicator(
                    color: AppColors.primary,
                    minHeight: 2,
                  ),
                ),

              // ==================================================
              // SEARCH SUGGESTIONS
              // ==================================================

              if (_suggestions.isNotEmpty)
                Container(
                  margin:
                  const EdgeInsets.only(top: 8),

                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius:
                    BorderRadius.circular(16),

                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),

                  child: Column(
                    children:
                    _suggestions.map((s) {

                      return InkWell(
                        onTap: () =>
                            _selectSuggestion(s),

                        child: Padding(
                          padding:
                          const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),

                          child: Row(
                            children: [

                              const Icon(
                                Icons.location_on_outlined,
                                color:
                                AppColors.textMuted,
                                size: 18,
                              ),

                              const SizedBox(
                                width: 10,
                              ),

                              Expanded(
                                child: Text(
                                  s.displayName,

                                  maxLines: 1,

                                  overflow:
                                  TextOverflow.ellipsis,

                                  style:
                                  AppTextStyles.body(
                                    size: 12.5,
                                    weight:
                                    FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 18),

              // ==================================================
              // QUICK ACTIONS
              // ==================================================

              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.stretch,

                  children: [

                    Expanded(
                      child:
                      _QuickActionCard(
                        icon:
                        Icons.bolt_rounded,

                        iconColor:
                        Colors.white,

                        iconBg:
                        AppColors.primary,

                        bgColor:
                        AppColors.primary
                            .withOpacity(0.08),

                        title:
                        'Nearby Chargers',

                        subtitle:
                        'Find available chargers near you',

                        arrowColor:
                        AppColors.primary,

                        onTap: () =>
                            _goToNearbyStations(
                              context,
                            ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child:
                      _QuickActionCard(
                        icon:
                        Icons.alt_route_rounded,

                        iconColor:
                        Colors.white,

                        iconBg:
                        AppColors.secondary,

                        bgColor:
                        AppColors.secondary
                            .withOpacity(0.08),

                        title:
                        'Plan a Trip',

                        subtitle:
                        'Find charging stops on your route',

                        arrowColor:
                        AppColors.secondary,

                        onTap: () =>
                            _goToTripPlanner(
                              context,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // ==================================================
              // NEARBY FOR YOU
              // ==================================================

              Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

                children: [

                  Text(
                    'Nearby for you',
                    style:
                    AppTextStyles.display(
                      size: 16,
                      weight: FontWeight.w800,
                    ),
                  ),

                  InkWell(
                    onTap: () =>
                        _goToNearbyStations(
                          context,
                        ),

                    child: Text(
                      'View all',
                      style:
                      AppTextStyles.body(
                        size: 13,
                        weight:
                        FontWeight.w700,
                        color:
                        AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ==================================================
              // REAL NEAREST STATION
              // ==================================================

              if (_isLoadingNearest)
                Container(
                  width: double.infinity,

                  padding:
                  const EdgeInsets.all(28),

                  decoration:
                  BoxDecoration(
                    color: AppColors.card,

                    borderRadius:
                    BorderRadius.circular(18),

                    border: Border.all(
                      color:
                      AppColors.border,
                    ),
                  ),

                  child: Column(
                    children: [

                      const SizedBox(
                        width: 26,
                        height: 26,

                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color:
                          AppColors.primary,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Finding the closest charging station...',
                        textAlign:
                        TextAlign.center,

                        style:
                        AppTextStyles.body(
                          size: 12,
                          color:
                          AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )

              else if (_nearestStation != null &&
                  _nearestDistanceKm != null)
                _NearestStationCard(
                  station:
                  _nearestStation!,

                  distanceKm:
                  _nearestDistanceKm!,

                  onViewMap: () =>
                      _goToNearbyStations(
                        context,
                      ),
                )

              else
                Container(
                  width: double.infinity,

                  padding:
                  const EdgeInsets.all(20),

                  decoration:
                  BoxDecoration(
                    color: AppColors.card,

                    borderRadius:
                    BorderRadius.circular(18),

                    border: Border.all(
                      color:
                      AppColors.border,
                    ),
                  ),

                  child: Column(
                    children: [

                      const Icon(
                        Icons.location_off_rounded,
                        size: 30,
                        color:
                        AppColors.textMuted,
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      Text(
                        _nearestError ??
                            'Unable to find a nearby station.',

                        textAlign:
                        TextAlign.center,

                        style:
                        AppTextStyles.body(
                          size: 12.5,
                          color:
                          AppColors.textMuted,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      OutlinedButton.icon(
                        onPressed:
                        _loadNearestStation,

                        icon:
                        const Icon(
                          Icons.refresh_rounded,
                          size: 17,
                        ),

                        label:
                        const Text(
                          'Try again',
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 26),

              // ==================================================
              // TAMIL NADU NETWORK
              // ==================================================

              Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

                children: [

                  Text(
                    'Tamil Nadu Network',
                    style:
                    AppTextStyles.display(
                      size: 16,
                      weight: FontWeight.w800,
                    ),
                  ),

                  Text(
                    'Live status',
                    style:
                    AppTextStyles.body(
                      size: 13,
                      weight:
                      FontWeight.w700,
                      color:
                      AppColors.primary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Container(
                padding:
                const EdgeInsets.symmetric(
                  vertical: 20,
                ),

                decoration:
                BoxDecoration(
                  color: AppColors.card,

                  borderRadius:
                  BorderRadius.circular(18),

                  border: Border.all(
                    color:
                    AppColors.border,
                  ),
                ),

                child: const Row(
                  children: [

                    Expanded(
                      child: _StatItem(
                        value: '881+',
                        label: 'Stations',
                        color:
                        AppColors.primary,
                      ),
                    ),

                    _StatDivider(),

                    Expanded(
                      child: _StatItem(
                        value: '32',
                        label: 'Districts',
                        color:
                        AppColors.secondary,
                      ),
                    ),

                    _StatDivider(),

                    Expanded(
                      child: _StatItem(
                        value: '99.2%',
                        label: 'Online',
                        color:
                        AppColors.primary,
                      ),
                    ),
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

// ================================================================
// QUICK ACTION CARD
// ================================================================

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color bgColor;
  final Color arrowColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.bgColor,
    required this.arrowColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius:
      BorderRadius.circular(18),

      child: Container(
        padding:
        const EdgeInsets.all(16),

        decoration:
        BoxDecoration(
          color: bgColor,

          borderRadius:
          BorderRadius.circular(18),

          border: Border.all(
            color:
            AppColors.border,
          ),
        ),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [

            Container(
              width: 44,
              height: 44,

              decoration:
              BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),

              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),

            const SizedBox(height: 14),

            Text(
              title,
              style:
              AppTextStyles.display(
                size: 14.5,
                weight:
                FontWeight.w800,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              subtitle,
              style:
              AppTextStyles.body(
                size: 11.5,
                color:
                AppColors.textMuted,
              ),
            ),

            const SizedBox(height: 12),

            Align(
              alignment:
              Alignment.bottomRight,

              child: Icon(
                Icons.arrow_forward_rounded,
                color: arrowColor,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// REAL NEAREST STATION CARD
// ================================================================

class _NearestStationCard extends StatelessWidget {
  final EvStation station;
  final double distanceKm;
  final VoidCallback onViewMap;

  const _NearestStationCard({
    required this.station,
    required this.distanceKm,
    required this.onViewMap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding:
      const EdgeInsets.all(14),

      decoration:
      BoxDecoration(
        color: AppColors.card,

        borderRadius:
        BorderRadius.circular(18),

        border: Border.all(
          color:
          AppColors.border,
        ),

        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset:
            const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [

          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [

              // Station icon
              Container(
                width: 72,
                height: 72,

                decoration:
                BoxDecoration(
                  color:
                  AppColors.primary
                      .withOpacity(0.10),

                  borderRadius:
                  BorderRadius.circular(16),
                ),

                child: const Icon(
                  Icons.ev_station_rounded,
                  color:
                  AppColors.primary,
                  size: 32,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [

                    Text(
                      station.name,

                      maxLines: 2,

                      overflow:
                      TextOverflow.ellipsis,

                      style:
                      AppTextStyles.display(
                        size: 15,
                        weight:
                        FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    // REAL DISTANCE
                    Row(
                      children: [

                        const Icon(
                          Icons.near_me_rounded,
                          size: 14,
                          color:
                          AppColors.primary,
                        ),

                        const SizedBox(
                          width: 4,
                        ),

                        Text(
                          '${distanceKm.toStringAsFixed(1)} km away',

                          style:
                          AppTextStyles.body(
                            size: 12,
                            weight:
                            FontWeight.w700,
                            color:
                            AppColors.primary,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 7),

                    // PORTS + CONNECTORS
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,

                      children: [

                        Row(
                          mainAxisSize:
                          MainAxisSize.min,

                          children: [

                            const Icon(
                              Icons.bolt_rounded,
                              size: 14,
                              color:
                              AppColors.textMuted,
                            ),

                            const SizedBox(
                              width: 3,
                            ),

                            Text(
                              '${station.totalPorts} ports',

                              style:
                              AppTextStyles.body(
                                size: 11.5,
                                color:
                                AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),

                        Row(
                          mainAxisSize:
                          MainAxisSize.min,

                          children: [

                            const Icon(
                              Icons.electrical_services_rounded,
                              size: 14,
                              color:
                              AppColors.textMuted,
                            ),

                            const SizedBox(
                              width: 3,
                            ),

                            Text(
                              station.connectorTypes,

                              maxLines: 1,

                              overflow:
                              TextOverflow.ellipsis,

                              style:
                              AppTextStyles.body(
                                size: 11.5,
                                color:
                                AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // OPERATOR
                    if (station.operatorName != null &&
                        station.operatorName!
                            .trim()
                            .isNotEmpty) ...[
                      const SizedBox(height: 4),

                      Text(
                        station.operatorName!,

                        maxLines: 1,

                        overflow:
                        TextOverflow.ellipsis,

                        style:
                        AppTextStyles.body(
                          size: 11,
                          color:
                          AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // VIEW ON MAP
          SizedBox(
            width: double.infinity,

            child:
            ElevatedButton.icon(
              onPressed: onViewMap,

              icon:
              const Icon(
                Icons.map_rounded,
                size: 18,
              ),

              label:
              const Text(
                'View Nearby Stations',
              ),

              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primary,

                foregroundColor:
                Colors.white,

                elevation: 0,

                padding:
                const EdgeInsets.symmetric(
                  vertical: 13,
                ),

                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// STAT ITEM
// ================================================================

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        Text(
          value,
          style:
          AppTextStyles.display(
            size: 19,
            weight:
            FontWeight.w800,
            color: color,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          label,
          style:
          AppTextStyles.body(
            size: 11,
            color:
            AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ================================================================
// STAT DIVIDER
// ================================================================

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.border,
    );
  }
}