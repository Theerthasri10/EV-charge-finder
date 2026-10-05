// lib/screens/trip_planner_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../models/ev_station.dart';
import '../services/ev_station_service.dart';
import '../services/directions_service.dart';
import '../services/geocoding_service.dart';
import '../utils/geo_utils.dart';
import 'station_detail_screen.dart';

class TripPlannerScreen extends StatefulWidget {
  const TripPlannerScreen({super.key});

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();

  bool get _keyboardVisible => MediaQuery.of(context).viewInsets.bottom > 0;

  final _geocodingService = GeocodingService();
  final _directionsService = DirectionsService();
  final _stationService = EvStationService();

  final MapController _mapController = MapController();

  LatLng? _originLatLng;
  LatLng? _destinationLatLng;

  List<PlaceSuggestion> _originSuggestions = [];
  List<PlaceSuggestion> _destinationSuggestions = [];
  Timer? _debounce;

  List<LatLng> _routePoints = [];

  double? _routeDistanceKm;
  int? _routeDurationMin;

  List<EvStation> _stationsOnRoute = [];
  bool _isLoading = false;
  bool _isLoadingLocation = true;
  String? _errorMessage;

  EvStation? _selectedStation;

  @override
  void initState() {
    super.initState();
    _prefillCurrentLocation();
  }

  // ============================================================
  // ORIGINAL LOGIC — UNCHANGED
  // ============================================================

  Future<void> _prefillCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(
        position.latitude,
        position.longitude,
      );

      final address =
      await _geocodingService.reverseGeocode(latLng);

      setState(() {
        _originLatLng = latLng;
        _originController.text =
            address ?? 'Current Location';
        _isLoadingLocation = false;
      });
    } catch (_) {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _onOriginChanged(String query) {
    _originLatLng = null;
    _debounce?.cancel();

    _debounce = Timer(
      const Duration(milliseconds: 500),
          () async {
        final results =
        await _geocodingService.autocomplete(query);

        if (mounted) {
          setState(() => _originSuggestions = results);
        }
      },
    );
  }

  void _onDestinationChanged(String query) {
    _destinationLatLng = null;
    _debounce?.cancel();

    _debounce = Timer(
      const Duration(milliseconds: 500),
          () async {
        final results =
        await _geocodingService.autocomplete(query);

        if (mounted) {
          setState(() => _destinationSuggestions = results);
        }
      },
    );
  }

  void _selectOriginSuggestion(
      PlaceSuggestion suggestion,
      ) {
    setState(() {
      _originController.text =
          suggestion.displayName;
      _originLatLng = suggestion.location;
      _originSuggestions = [];
    });
  }

  void _selectDestinationSuggestion(
      PlaceSuggestion suggestion,
      ) {
    setState(() {
      _destinationController.text =
          suggestion.displayName;
      _destinationLatLng = suggestion.location;
      _destinationSuggestions = [];
    });
  }

  void _selectStation(EvStation station) {
    setState(() => _selectedStation = station);
  }

  void _clearSelection() {
    setState(() => _selectedStation = null);
  }

  Future<void> _planTrip() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeDurationMin = null;
      _stationsOnRoute = [];
      _selectedStation = null;
    });

    try {
      final origin = _originLatLng ??
          await _geocodingService.geocode(
            _originController.text.trim(),
          );

      final destination = _destinationLatLng ??
          await _geocodingService.geocode(
            _destinationController.text.trim(),
          );

      if (origin == null || destination == null) {
        setState(() {
          _errorMessage =
          'Could not find one of the locations. '
              'Try selecting from suggestions.';
          _isLoading = false;
        });
        return;
      }

      final route =
      await _directionsService.getRoute(
        origin,
        destination,
      );

      if (route == null) {
        setState(() {
          _errorMessage =
          'Could not find a route between these locations.';
          _isLoading = false;
        });
        return;
      }

      final allStations =
      await _stationService.getAllStations();

      final onRoute = allStations.where((station) {
        final distance =
        GeoUtils.distanceToRouteKm(
          station.latitude,
          station.longitude,
          route.points,
        );

        return distance <= 5.0;
      }).toList();

      setState(() {
        _routePoints = route.points;
        _routeDistanceKm = route.distanceKm;
        _routeDurationMin = route.durationMinutes;
        _stationsOnRoute = onRoute;
        _isLoading = false;
      });

      _fitMapToRoute(route.points);
    } catch (e) {
      setState(() {
        _errorMessage = 'Something went wrong: $e';
        _isLoading = false;
      });
    }
  }

  void _fitMapToRoute(List<LatLng> route) {
    if (route.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final bounds = LatLngBounds.fromPoints(route);

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    });
  }

  String _formatDuration(int minutes) {
    final hrs = minutes ~/ 60;
    final mins = minutes % 60;

    if (hrs == 0) return '$mins min';
    if (mins == 0) return '$hrs hr';

    return '$hrs hr $mins min';
  }

  // ============================================================
  // ENHANCED UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: Column(
                children: [
                  _buildTripForm(),

                  if (_routeDistanceKm != null &&
                      _routeDurationMin != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        10,
                      ),
                      child: _SuggestedRouteCard(
                        distanceKm: _routeDistanceKm!,
                        durationLabel:
                        _formatDuration(_routeDurationMin!),
                        chargingStops:
                        _stationsOnRoute.length,
                      ),
                    ),

                  Expanded(
                    child: _buildMap(),
                  ),

                  if (_stationsOnRoute.isNotEmpty && !_keyboardVisible)
                    _buildStationList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        14,
        20,
        10,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.alt_route_rounded,
              color: AppColors.primary,
              size: 23,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Planner',
                  style: AppTextStyles.display(
                    size: 19,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Find chargers along your journey',
                  style: AppTextStyles.body(
                    size: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.border,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.ev_station_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  'EV Route',
                  style: AppTextStyles.body(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TRIP FORM
  // ============================================================

  Widget _buildTripForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        8,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _LocationDot(
                      color: AppColors.primary,
                      icon: Icons.my_location_rounded,
                    ),

                    Container(
                      width: 1,
                      height: 34,
                      color: AppColors.border,
                    ),

                    _LocationDot(
                      color: AppColors.secondary,
                      icon: Icons.location_on_rounded,
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    children: [
                      _RouteField(
                        controller: _originController,
                        hint: 'Starting point',
                        icon: Icons.trip_origin_rounded,
                        iconColor: AppColors.primary,
                        onChanged: _onOriginChanged,
                        trailing: _isLoadingLocation
                            ? const SizedBox(
                          height: 16,
                          width: 16,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                            AppColors.primary,
                          ),
                        )
                            : null,
                      ),

                      _buildSuggestionsList(
                        _originSuggestions,
                        _selectOriginSuggestion,
                      ),

                      const SizedBox(height: 9),

                      _RouteField(
                        controller:
                        _destinationController,
                        hint: 'Where are you going?',
                        icon: Icons.flag_rounded,
                        iconColor:
                        AppColors.secondary,
                        onChanged:
                        _onDestinationChanged,
                      ),

                      _buildSuggestionsList(
                        _destinationSuggestions,
                        _selectDestinationSuggestion,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                _isLoading ? null : _planTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primary,
                  disabledBackgroundColor:
                  AppColors.primary.withOpacity(0.45),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(15),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration:
                  const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const SizedBox(
                    key: ValueKey('loading'),
                    height: 20,
                    width: 20,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                      : Row(
                    key: const ValueKey('button'),
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.route_rounded,
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Plan My Route',
                        style:
                        AppTextStyles.display(
                          size: 14,
                          weight:
                          FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_errorMessage != null)
              Padding(
                padding:
                const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                    AppColors.error.withOpacity(0.07),
                    borderRadius:
                    BorderRadius.circular(12),
                    border: Border.all(
                      color:
                      AppColors.error.withOpacity(0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 17,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style:
                          AppTextStyles.body(
                            size: 11.5,
                            color:
                            AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAP
  // ============================================================

  Widget _buildMap() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        2,
        16,
        10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                const LatLng(12.9716, 77.5946),
                initialZoom: 10,
                onTap: (_, __) => _clearSelection(),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName:
                  'com.yourteam.evchargefinder',
                ),

                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        color: AppColors.secondary,
                        strokeWidth: 5,
                      ),
                    ],
                  ),

                MarkerLayer(
                  markers:
                  _stationsOnRoute.map((station) {
                    final isSelected =
                        _selectedStation?.id ==
                            station.id;

                    return Marker(
                      point: LatLng(
                        station.latitude,
                        station.longitude,
                      ),
                      width:
                      isSelected ? 44 : 34,
                      height:
                      isSelected ? 44 : 34,
                      child: GestureDetector(
                        onTap: () =>
                            _selectStation(station),
                        child: _RouteMapPin(
                          highlighted:
                          isSelected,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            // MAP LABEL
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color:
                  Colors.white.withOpacity(0.94),
                  borderRadius:
                  BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withOpacity(0.10),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.map_rounded,
                      size: 15,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _routePoints.isEmpty
                          ? 'Route map'
                          : 'Your route',
                      style:
                      AppTextStyles.body(
                        size: 11,
                        weight:
                        FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // MAP LEGEND
            if (_routePoints.isNotEmpty)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withOpacity(0.94),
                    borderRadius:
                    BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(0.10),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                        const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${_stationsOnRoute.length} chargers',
                        style:
                        AppTextStyles.body(
                          size: 10.5,
                          weight:
                          FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // SELECTED STATION
            if (_selectedStation != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _StationPopupCard(
                  station: _selectedStation!,
                  onClose: _clearSelection,
                  onTap: () =>
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              StationDetailScreen(
                                station:
                                _selectedStation!,
                              ),
                        ),
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STATION LIST
  // ============================================================

  Widget _buildStationList() {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius:
        const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),

          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius:
              BorderRadius.circular(10),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              9,
              20,
              7,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Charging stops',
                        style:
                        AppTextStyles.display(
                          size: 14,
                          weight:
                          FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withOpacity(0.10),
                          borderRadius:
                          BorderRadius.circular(
                              8),
                        ),
                        child: Text(
                          '${_stationsOnRoute.length}',
                          style:
                          AppTextStyles.body(
                            size: 10,
                            weight:
                            FontWeight.w800,
                            color:
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Within 5 km of route',
                  style: AppTextStyles.body(
                    size: 10.5,
                    color:
                    AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding:
              const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              itemCount:
              _stationsOnRoute.length,
              itemBuilder:
                  (context, index) {
                final station =
                _stationsOnRoute[index];

                return _RouteStationCard(
                  station: station,
                  onTap: () {
                    _mapController.move(
                      LatLng(
                        station.latitude,
                        station.longitude,
                      ),
                      15,
                    );

                    _selectStation(station);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUGGESTIONS
  // ============================================================

  Widget _buildSuggestionsList(
      List<PlaceSuggestion> suggestions,
      void Function(PlaceSuggestion) onSelect,
      ) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints:
      const BoxConstraints(maxHeight: 150),
      margin:
      const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
        const Divider(
          height: 1,
          indent: 42,
        ),
        itemBuilder:
            (context, index) {
          final suggestion =
          suggestions[index];

          return InkWell(
            onTap: () =>
                onSelect(suggestion),
            child: Padding(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.secondary
                          .withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color:
                      AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      suggestion.displayName,
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      AppTextStyles.body(
                        size: 11.5,
                        weight:
                        FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }
}

// ============================================================
// LOCATION DOT
// ============================================================

class _LocationDot extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _LocationDot({
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 14,
        color: color,
      ),
    );
  }
}

// ============================================================
// ROUTE FIELD
// ============================================================

class _RouteField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  const _RouteField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.iconColor,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: iconColor,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppTextStyles.body(
                size: 12.5,
                weight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                AppTextStyles.body(
                  size: 12.5,
                  color:
                  AppColors.textMuted,
                ),
                border:
                InputBorder.none,
                isDense: true,
                contentPadding:
                EdgeInsets.zero,
              ),
            ),
          ),

          if (trailing != null)
            trailing!,
        ],
      ),
    );
  }
}

// ============================================================
// SUGGESTED ROUTE
// ============================================================

class _SuggestedRouteCard
    extends StatelessWidget {
  final double distanceKm;
  final String durationLabel;
  final int chargingStops;

  const _SuggestedRouteCard({
    required this.distanceKm,
    required this.durationLabel,
    required this.chargingStops,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary
                .withOpacity(0.12),
            AppColors.secondary
                .withOpacity(0.06),
          ],
        ),
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary
              .withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
            const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'Route ready',
                  style:
                  AppTextStyles.display(
                    size: 13.5,
                    weight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Charging stations found along your route',
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  AppTextStyles.body(
                    size: 10.5,
                    color:
                    AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Column(
            crossAxisAlignment:
            CrossAxisAlignment.end,
            children: [
              Text(
                '${distanceKm.toStringAsFixed(0)} km',
                style:
                AppTextStyles.display(
                  size: 14,
                  weight:
                  FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$durationLabel · $chargingStops stops',
                style:
                AppTextStyles.body(
                  size: 9.5,
                  color:
                  AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MAP PIN
// ============================================================

class _RouteMapPin
    extends StatelessWidget {
  final bool highlighted;

  const _RouteMapPin({
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
      const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.secondary
            : AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: highlighted ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (highlighted
                ? AppColors.secondary
                : AppColors.primary)
                .withOpacity(0.45),
            blurRadius:
            highlighted ? 14 : 7,
          ),
        ],
      ),
      child: Icon(
        Icons.bolt_rounded,
        color: Colors.white,
        size: highlighted ? 20 : 15,
      ),
    );
  }
}

// ============================================================
// SELECTED STATION POPUP
// ============================================================

class _StationPopupCard
    extends StatelessWidget {
  final EvStation station;
  final VoidCallback onClose;
  final VoidCallback onTap;

  const _StationPopupCard({
    required this.station,
    required this.onClose,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(18),
        child: Container(
          padding:
          const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius:
            BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withOpacity(0.15),
                blurRadius: 22,
                offset:
                const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary
                      .withOpacity(0.10),
                  borderRadius:
                  BorderRadius.circular(
                      13),
                ),
                child: const Icon(
                  Icons.ev_station_rounded,
                  color:
                  AppColors.primary,
                  size: 22,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      AppTextStyles.display(
                        size: 13,
                        weight:
                        FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${station.totalPorts} ports · ${station.connectorTypes}'
                          '${station.operatorName != null ? ' · ${station.operatorName}' : ''}',
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      AppTextStyles.body(
                        size: 10.5,
                        color:
                        AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tap to view station details',
                      style:
                      AppTextStyles.body(
                        size: 9.5,
                        weight:
                        FontWeight.w600,
                        color:
                        AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              IconButton(
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                ),
                color:
                AppColors.textMuted,
                iconSize: 18,
                padding:
                EdgeInsets.zero,
                constraints:
                const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HORIZONTAL STATION CARD
// ============================================================

class _RouteStationCard
    extends StatelessWidget {
  final EvStation station;
  final VoidCallback onTap;

  const _RouteStationCard({
    required this.station,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius:
      BorderRadius.circular(16),
      child: Container(
        width: 250,
        margin:
        const EdgeInsets.only(
          right: 10,
          bottom: 10,
        ),
        padding:
        const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius:
          BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary
                    .withOpacity(0.10),
                borderRadius:
                BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color:
                AppColors.primary,
                size: 21,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    AppTextStyles.body(
                      size: 12,
                      weight:
                      FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '${station.totalPorts} ports',
                    style:
                    AppTextStyles.body(
                      size: 10,
                      color:
                      AppColors.textMuted,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    station.connectorTypes,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    AppTextStyles.body(
                      size: 9.5,
                      color:
                      AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color:
              AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}