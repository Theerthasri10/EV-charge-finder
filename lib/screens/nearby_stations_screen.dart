// lib/screens/nearby_stations_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../models/ev_station.dart';
import '../services/ev_station_service.dart';
import '../services/geocoding_service.dart';
import '../utils/geo_utils.dart';
import 'station_detail_screen.dart';

class NearbyStationsScreen extends StatefulWidget {
  final String? initialQuery;

  const NearbyStationsScreen({super.key, this.initialQuery});

  @override
  State<NearbyStationsScreen> createState() => _NearbyStationsScreenState();
}

class _NearbyStationsScreenState extends State<NearbyStationsScreen> {
  final _service = EvStationService();
  final _geocodingService = GeocodingService();
  final MapController _mapController = MapController();

  final TextEditingController _searchController = TextEditingController();

  static const List<double> _radiusSteps = [5, 10, 20, 50, 100];

  LatLng? _currentPosition;
  String _currentAddress = 'Locating you...';

  List<MapEntry<EvStation, double>> _nearbyStations = [];
  double? _activeRadiusKm;

  bool _isLoading = true;
  String? _errorMessage;

  EvStation? _selectedStation;
  double? _selectedDistance;

  String _selectedFilter = 'All';
  final List<String> _filterOptions = const [
    'All',
    'Fast Charger',
    'Available',
    'CCS2',
    '24x7',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      _searchTypedLocation();
    } else {
      _loadNearbyStations();
    }
  }

  // ================= GPS-BASED LOAD (locate-me flow, unchanged trigger points) =================
  Future<void> _loadNearbyStations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('STEP 1: Checking location service...');
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('STEP 1 DONE: serviceEnabled = $serviceEnabled');

      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Please turn on location services.';
          _isLoading = false;
        });
        return;
      }

      print('STEP 2: Checking permission...');
      LocationPermission permission = await Geolocator.checkPermission();
      print('STEP 2 DONE: permission = $permission');

      if (permission == LocationPermission.denied) {
        print('STEP 2b: Requesting permission...');
        permission = await Geolocator.requestPermission();
        print('STEP 2b DONE: permission = $permission');
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permission denied.';
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Location permission permanently denied. Enable it in settings.';
          _isLoading = false;
        });
        return;
      }

      print('STEP 3: Getting current position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      print('STEP 3 DONE: lat=${position.latitude}, lng=${position.longitude}');

      final currentLatLng = LatLng(position.latitude, position.longitude);

      // Reverse geocode: fills the "Locating you..." label AND autofills the search box
      _geocodingService.reverseGeocode(currentLatLng).then((address) {
        print('GEOCODE SUCCESS: address = $address');
        if (!mounted) return;
        final resolvedAddress = address ?? 'Current Location';
        setState(() => _currentAddress = resolvedAddress);
        if (_searchController.text.isEmpty || _searchController.text == 'Locating you...') {
          _searchController.text = resolvedAddress;
        }
      }).catchError((e) {
        print('GEOCODE ERROR: $e');
        if (!mounted) return;
        if (_searchController.text.isEmpty || _searchController.text == 'Locating you...') {
          _searchController.text = 'Current Location';
        }
      });

      await _loadStationsAround(currentLatLng);
    } catch (e, stackTrace) {
      print('ERROR CAUGHT: $e');
      print('STACK TRACE: $stackTrace');
      setState(() {
        _errorMessage = 'Could not load stations: $e';
        _isLoading = false;
      });
    }
  }

  // ================= SEARCH-BASED LOAD (search icon flow) =================
  Future<void> _searchTypedLocation() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      // Nothing typed — fall back to a normal GPS reload
      _loadNearbyStations();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('SEARCH: geocoding "$query"...');
      final foundLocation = await _geocodingService.geocode(query).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Location search timed out.'),
      );

      if (foundLocation == null) {
        setState(() {
          _errorMessage = 'Could not find "$query". Try a different search.';
          _isLoading = false;
        });
        return;
      }

      print('SEARCH DONE: lat=${foundLocation.latitude}, lng=${foundLocation.longitude}');

      setState(() => _currentAddress = query);

      await _loadStationsAround(foundLocation);
    } catch (e, stackTrace) {
      print('SEARCH ERROR: $e');
      print('STACK TRACE: $stackTrace');
      setState(() {
        _errorMessage = 'Could not search location: $e';
        _isLoading = false;
      });
    }
  }

  // ================= SHARED: fetch stations + compute distances around ANY point =================
  Future<void> _loadStationsAround(LatLng point) async {
    print('STEP 4: Fetching all stations from backend...');
    final allStations = await _service.getAllStations().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception(
        'Server took too long to respond. Check your backend is running and reachable.',
      ),
    );
    print('STEP 4 DONE: got ${allStations.length} stations');

    final withDistance = allStations.map((station) {
      final distance = GeoUtils.distanceKm(
        point.latitude,
        point.longitude,
        station.latitude,
        station.longitude,
      );
      return MapEntry(station, distance);
    }).toList();

    withDistance.sort((a, b) => a.value.compareTo(b.value));

    final result = _selectWithinAdaptiveRadius(withDistance);
    print('STEP 5 DONE: ${result.stations.length} stations selected, radius=${result.radiusKm}');

    setState(() {
      _currentPosition = point;
      _nearbyStations = result.stations;
      _activeRadiusKm = result.radiusKm;
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(point, 13);
    });
  }

  ({List<MapEntry<EvStation, double>> stations, double? radiusKm}) _selectWithinAdaptiveRadius(
      List<MapEntry<EvStation, double>> sortedByDistance,
      ) {
    for (final radius in _radiusSteps) {
      final withinRadius = sortedByDistance.where((e) => e.value <= radius).toList();
      if (withinRadius.isNotEmpty) {
        return (stations: withinRadius, radiusKm: radius);
      }
    }
    return (stations: sortedByDistance.take(5).toList(), radiusKm: null);
  }

  void _selectStation(EvStation station, double distance) {
    setState(() {
      _selectedStation = station;
      _selectedDistance = distance;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedStation = null;
      _selectedDistance = null;
    });
  }

  String _bannerText() {
    if (_isLoading) return 'Searching for stations...';
    if (_errorMessage != null) return _errorMessage!;
    if (_activeRadiusKm == null) {
      return 'No stations nearby — showing the closest ${_nearbyStations.length}';
    }
    return 'Showing ${_nearbyStations.length} stations within ${_activeRadiusKm!.toInt()} km';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ================= TOP APP BAR =================
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back_rounded, size: 22),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Nearby Stations',
                      style: AppTextStyles.display(size: 18, weight: FontWeight.w800),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.tune_rounded, size: 20, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),

            // ================= FUNCTIONAL SEARCH BAR =================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: AppTextStyles.body(size: 13.5, weight: FontWeight.w600),
                        onSubmitted: (_) => _searchTypedLocation(),
                        decoration: InputDecoration(
                          hintText: 'Search station or area',
                          hintStyle: AppTextStyles.body(size: 13.5, color: AppColors.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _searchTypedLocation,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.search_rounded, color: AppColors.primary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ================= FILTER CHIPS =================
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filterOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final label = _filterOptions[index];
                  final selected = label == _selectedFilter;
                  return _FilterChip(
                    label: label,
                    selected: selected,
                    onTap: () => setState(() => _selectedFilter = label),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            // ================= MAP CARD =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 260,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentPosition ?? const LatLng(13.0827, 80.2707),
                          initialZoom: 13,
                          onTap: (_, __) => _clearSelection(),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.yourteam.evchargefinder',
                          ),
                          MarkerLayer(
                            markers: [
                              if (_currentPosition != null)
                                Marker(
                                  point: _currentPosition!,
                                  width: 30,
                                  height: 30,
                                  child: const _MapPin(icon: Icons.my_location, isUser: true),
                                ),
                              ..._nearbyStations.map((entry) {
                                final station = entry.key;
                                final distance = entry.value;
                                return Marker(
                                  point: LatLng(station.latitude, station.longitude),
                                  width: 30,
                                  height: 30,
                                  child: GestureDetector(
                                    onTap: () => _selectStation(station, distance),
                                    child: const _MapPin(icon: Icons.bolt, isUser: false),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: InkWell(
                          onTap: _loadNearbyStations, // GPS reload, unchanged
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.my_location_rounded, color: AppColors.secondary, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ================= BANNER TEXT =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _bannerText(),
                  style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ================= STATION LIST =================
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _errorMessage != null
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off, color: AppColors.error, size: 32),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(size: 12.5, color: AppColors.error),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(onPressed: _loadNearbyStations, child: const Text('Retry')),
                    ],
                  ),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: _nearbyStations.length,
                itemBuilder: (context, index) {
                  final station = _nearbyStations[index].key;
                  final distance = _nearbyStations[index].value;
                  return _StationRow(
                    station: station,
                    distanceKm: distance,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => StationDetailScreen(station: station)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= FILTER CHIP =================
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.body(
              size: 12,
              weight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ================= MAP PIN =================
class _MapPin extends StatelessWidget {
  final IconData icon;
  final bool isUser;
  const _MapPin({required this.icon, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isUser ? AppColors.secondary : AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: (isUser ? AppColors.secondary : AppColors.primary).withValues(alpha: 0.5), blurRadius: 10),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 14),
    );
  }
}

// ================= STATION ROW =================
class _StationRow extends StatelessWidget {
  final EvStation station;
  final double? distanceKm;
  final VoidCallback onTap;

  const _StationRow({required this.station, this.distanceKm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.display(size: 14, weight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  distanceKm != null ? '${distanceKm!.toStringAsFixed(1)} km away' : '',
                  style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '${station.totalPorts} ports · ${station.connectorTypes}'
                      '${station.operatorName != null ? ' · ${station.operatorName}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text('View', style: AppTextStyles.body(size: 11.5, weight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}