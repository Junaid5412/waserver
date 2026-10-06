import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String name;
  final String address;
  final bool isLive;
  final int? liveDurationMinutes;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.address,
    this.isLive = false,
    this.liveDurationMinutes,
  });
}

class LocationPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String? initialName;

  const LocationPickerScreen({
    super.key,
    this.initialLat = 24.8607,
    this.initialLng = 67.0011,
    this.initialName,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late double _lat;
  late double _lng;
  int _zoom = 15;

  String _placeName = 'Fetching location details...';
  String _address = '';
  bool _isGeocoding = false;
  Timer? _geocodeDebounce;

  // GPS State
  bool _isLocatingGps = false;
  bool _gpsAcquired = false;
  bool _permissionDenied = false;

  // Database-backed Saved Locations
  List<Map<String, dynamic>> _savedLocations = [];
  bool _isLoadingSaved = false;

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _placeName = widget.initialName!;
    }

    _loadSavedLocations();
    _initAndAcquireGps();
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedLocations() async {
    setState(() => _isLoadingSaved = true);
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final list = await auth.api.getSavedLocations();
      if (mounted) {
        setState(() {
          _savedLocations = list;
          _isLoadingSaved = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSaved = false);
    }
  }

  Future<void> _initAndAcquireGps({bool forceRequest = true}) async {
    if (!mounted) return;
    setState(() {
      _isLocatingGps = true;
      _permissionDenied = false;
    });

    try {
      // 1. Check & request permission
      bool permitted = await LocationService.hasPermission();
      if (!permitted && forceRequest) {
        permitted = await LocationService.requestPermission();
      }

      if (!permitted) {
        if (mounted) {
          setState(() {
            _isLocatingGps = false;
            _permissionDenied = true;
          });
          _reverseGeocode(_lat, _lng);
        }
        return;
      }

      // 2. Check if GPS service is enabled
      final isEnabled = await LocationService.isLocationServiceEnabled();
      if (!isEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location services are turned off on your device.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => LocationService.openSettings(),
            ),
          ),
        );
      }

      // 3. Acquire GPS coordinates
      final loc = await LocationService.getCurrentLocation(requestIfDenied: false);
      if (loc != null && mounted) {
        setState(() {
          _lat = loc.latitude;
          _lng = loc.longitude;
          _gpsAcquired = true;
          _isLocatingGps = false;
          _permissionDenied = false;
        });
        _reverseGeocode(_lat, _lng);
        return;
      }
    } catch (e) {
      debugPrint('[LocationPicker] GPS acquisition error: $e');
    }

    if (mounted) {
      setState(() => _isLocatingGps = false);
      _reverseGeocode(_lat, _lng);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size mapSize) {
    setState(() {
      final metersPerPixel = (156543.03392 * math.cos(_lat * math.pi / 180.0)) / math.pow(2, _zoom);
      final deltaLat = (details.delta.dy * metersPerPixel) / 111320.0;
      final deltaLng = -(details.delta.dx * metersPerPixel) / (111320.0 * math.cos(_lat * math.pi / 180.0));

      _lat = (_lat + deltaLat).clamp(-85.0, 85.0);
      _lng = (_lng + deltaLng);
      while (_lng > 180) _lng -= 360;
      while (_lng < -180) _lng += 360;
    });

    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 600), () {
      _reverseGeocode(_lat, _lng);
    });
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1&accept-language=en',
      );
      final res = await http.get(url, headers: {'User-Agent': 'ZelonMessenger/1.0'}).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final displayName = data['display_name']?.toString() ?? '';

        String title = addr['amenity'] ??
            addr['building'] ??
            addr['shop'] ??
            addr['tourism'] ??
            addr['road'] ??
            addr['neighbourhood'] ??
            addr['suburb'] ??
            addr['city'] ??
            'Selected Location';

        final parts = [
          addr['road'],
          addr['neighbourhood'] ?? addr['suburb'],
          addr['city'] ?? addr['town'] ?? addr['county'],
          addr['country']
        ].where((e) => e != null && e.toString().isNotEmpty).toList();

        final subtitle = parts.isNotEmpty ? parts.join(', ') : displayName;

        if (mounted) {
          setState(() {
            _placeName = title;
            _address = subtitle;
            _isGeocoding = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _placeName = 'Location Pin';
        _address = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
        _isGeocoding = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=5&accept-language=en',
        );
        final res = await http.get(url, headers: {'User-Agent': 'ZelonMessenger/1.0'}).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          if (mounted) {
            setState(() {
              _searchResults = list.map((e) => Map<String, dynamic>.from(e)).toList();
              _isSearching = false;
            });
          }
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _isSearching = false);
    });
  }

  void _selectSearchResult(Map<String, dynamic> item) {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lng = double.tryParse(item['lon']?.toString() ?? '');
    if (lat != null && lng != null) {
      setState(() {
        _lat = lat;
        _lng = lng;
        _placeName = item['name']?.toString() ?? item['display_name']?.toString().split(',').first ?? 'Location';
        _address = item['display_name']?.toString() ?? '';
        _searchResults = [];
        _searchCtrl.clear();
      });
      FocusScope.of(context).unfocus();
    }
  }

  void _openSaveLocationDialog() {
    final labelCtrl = TextEditingController(text: 'Home');
    final nameCtrl = TextEditingController(text: _placeName);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.bookmark_add_rounded, color: WhatsAppTheme.primaryGreen),
                  SizedBox(width: 8),
                  Text('Save to Database', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select or type a label to save this position permanently:',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: ['Home', 'Office', 'Warehouse', 'Branch'].map((lbl) {
                      final isSel = labelCtrl.text.toLowerCase() == lbl.toLowerCase();
                      return ChoiceChip(
                        label: Text(lbl),
                        selected: isSel,
                        selectedColor: WhatsAppTheme.primaryGreen.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSel ? WhatsAppTheme.primaryGreen : null,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          if (val) setDlgState(() => labelCtrl.text = lbl);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Label Name (e.g. Home, Office)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Place Description / Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WhatsAppTheme.primaryGreen,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final label = labelCtrl.text.trim();
                          final name = nameCtrl.text.trim();
                          if (label.isEmpty) return;

                          setDlgState(() => isSaving = true);
                          try {
                            final auth = Provider.of<AuthService>(context, listen: false);
                            await auth.api.saveUserLocation(
                              label: label,
                              name: name.isNotEmpty ? name : label,
                              address: _address,
                              latitude: _lat,
                              longitude: _lng,
                            );
                            await _loadSavedLocations();
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Saved "$label" to database successfully!'),
                                  backgroundColor: WhatsAppTheme.primaryGreen,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
                              );
                            }
                          } finally {
                            if (mounted) setDlgState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save to DB', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLiveLocationDurationSheet() {
    int selectedMinutes = 60; // Default 1 hour
    final captionCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: WhatsAppTheme.primaryGreen.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sensors_rounded, color: WhatsAppTheme.primaryGreen, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share Live Location',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Participants in this chat will see your real-time position',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const Text('Select Duration:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildDurationChoice(
                        minutes: 15,
                        label: '15 Minutes',
                        isSelected: selectedMinutes == 15,
                        onTap: () => setSheetState(() => selectedMinutes = 15),
                      ),
                      const SizedBox(width: 8),
                      _buildDurationChoice(
                        minutes: 60,
                        label: '1 Hour',
                        isSelected: selectedMinutes == 60,
                        onTap: () => setSheetState(() => selectedMinutes = 60),
                      ),
                      const SizedBox(width: 8),
                      _buildDurationChoice(
                        minutes: 480,
                        label: '8 Hours',
                        isSelected: selectedMinutes == 480,
                        onTap: () => setSheetState(() => selectedMinutes = 480),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: captionCtrl,
                    decoration: InputDecoration(
                      hintText: 'Add an optional status comment...',
                      prefixIcon: const Icon(Icons.comment_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WhatsAppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(
                        this.context,
                        LocationResult(
                          latitude: _lat,
                          longitude: _lng,
                          name: captionCtrl.text.trim().isNotEmpty ? captionCtrl.text.trim() : _placeName,
                          address: _address,
                          isLive: true,
                          liveDurationMinutes: selectedMinutes,
                        ),
                      );
                    },
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'Start Sharing Live Location',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDurationChoice({
    required int minutes,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? WhatsAppTheme.primaryGreen.withOpacity(0.12) : Colors.grey.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? WhatsAppTheme.primaryGreen : Colors.grey.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 20,
                color: isSelected ? WhatsAppTheme.primaryGreen : Colors.grey,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? WhatsAppTheme.primaryGreen : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Slippy math
  static int _lon2tile(double lon, int zoom) => ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  static int _lat2tile(double lat, int zoom) =>
      ((1.0 - math.log(math.tan(lat * math.pi / 180.0) + 1.0 / math.cos(lat * math.pi / 180.0)) / math.pi) / 2.0 * (1 << zoom)).floor();

  static double _tile2lon(int x, int zoom) => x / (1 << zoom) * 360.0 - 180.0;
  static double _tile2lat(int y, int zoom) {
    final n = math.pi - 2.0 * math.pi * y / (1 << zoom);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  Widget _buildMapTiles(Size size) {
    final centerTileX = _lon2tile(_lng, _zoom);
    final centerTileY = _lat2tile(_lat, _zoom);

    final tileSize = 256.0;
    final offsetX = (centerTileX - ((_lng + 180.0) / 360.0 * (1 << _zoom))) * tileSize;
    final offsetY = (centerTileY - ((1.0 - math.log(math.tan(_lat * math.pi / 180.0) + 1.0 / math.cos(_lat * math.pi / 180.0)) / math.pi) / 2.0 * (1 << _zoom))) * tileSize;

    final tiles = <Widget>[];

    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        final tx = centerTileX + dx;
        final ty = centerTileY + dy;
        final maxTile = (1 << _zoom) - 1;
        if (ty < 0 || ty > maxTile) continue;
        final wrappedTx = (tx % (1 << _zoom) + (1 << _zoom)) % (1 << _zoom);

        final tileUrl = 'https://mt1.google.com/vt/lyrs=m&hl=en&x=$wrappedTx&y=$ty&z=$_zoom';

        final left = (size.width / 2) + (dx * tileSize) + offsetX;
        final top = (size.height / 2) + (dy * tileSize) + offsetY;

        tiles.add(
          Positioned(
            left: left,
            top: top,
            width: tileSize,
            height: tileSize,
            child: Image.network(
              tileUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.network(
                'https://tile.openstreetmap.org/$_zoom/$wrappedTx/$ty.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFE8ECEF),
                  child: const Center(
                    child: Icon(Icons.map_outlined, color: Colors.black12, size: 24),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return Stack(children: tiles);
  }

  IconData _iconForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('home')) return Icons.home_rounded;
    if (lower.contains('office') || lower.contains('work')) return Icons.business_rounded;
    if (lower.contains('warehouse') || lower.contains('store')) return Icons.store_rounded;
    if (lower.contains('gym')) return Icons.fitness_center_rounded;
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: isDark ? WhatsAppTheme.surfaceDark : WhatsAppTheme.primaryGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isLocatingGps)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: Icon(
                _gpsAcquired ? Icons.my_location_rounded : Icons.location_searching_rounded,
                color: Colors.white,
              ),
              tooltip: 'Acquire Current GPS Location',
              onPressed: () => _initAndAcquireGps(forceRequest: true),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            children: [
              // 1. Interactive Map
              GestureDetector(
                onPanUpdate: (d) => _onPanUpdate(d, size),
                child: Container(
                  width: size.width,
                  height: size.height,
                  color: const Color(0xFFE5E9EC),
                  child: ClipRect(
                    child: _buildMapTiles(size),
                  ),
                ),
              ),

              // 2. Center Animated Pin Marker
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: Text(
                        _isGeocoding ? 'Locating...' : _placeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Icon(
                      Icons.location_on_rounded,
                      size: 44,
                      color: Color(0xFFE53935),
                    ),
                    Container(
                      width: 12,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),

              // 3. Zoom Controls (+ / -) & Center GPS FAB
              Positioned(
                right: 16,
                top: 80,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'gps_fab',
                      backgroundColor: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                      foregroundColor: WhatsAppTheme.primaryGreen,
                      onPressed: () => _initAndAcquireGps(forceRequest: true),
                      tooltip: 'Center on my GPS',
                      child: _isLocatingGps
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryGreen),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'zoom_in',
                      backgroundColor: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                      foregroundColor: WhatsAppTheme.primaryGreen,
                      onPressed: () {
                        if (_zoom < 18) setState(() => _zoom++);
                      },
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 6),
                    FloatingActionButton.small(
                      heroTag: 'zoom_out',
                      backgroundColor: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                      foregroundColor: WhatsAppTheme.primaryGreen,
                      onPressed: () {
                        if (_zoom > 3) setState(() => _zoom--);
                      },
                      child: const Icon(Icons.remove),
                    ),
                  ],
                ),
              ),

              // 4. Place Search Bar
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: Column(
                  children: [
                    Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search city, landmark or street...',
                          hintStyle: TextStyle(fontSize: 13.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                          prefixIcon: const Icon(Icons.search, color: WhatsAppTheme.primaryGreen, size: 20),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryGreen),
                                  ),
                                )
                              : _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),

                    if (_searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                        ),
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final item = _searchResults[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on_outlined, color: WhatsAppTheme.primaryGreen, size: 20),
                              title: Text(item['name'] ?? item['display_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(item['display_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                              onTap: () => _selectSearchResult(item),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              // 5. Permission Warning Banner (if denied)
              if (_permissionDenied)
                Positioned(
                  top: 66,
                  left: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_disabled_rounded, color: Colors.orange, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'GPS permission needed for accurate location.',
                            style: TextStyle(fontSize: 12, color: Colors.brown, fontWeight: FontWeight.w500),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _initAndAcquireGps(forceRequest: true),
                          child: const Text('Allow Access', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),

              // 6. Bottom Location Info & Actions Sheet
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -3))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Database-backed Saved Places (NO hardcoded Home/Office/Airport!)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Current GPS center button
                            ActionChip(
                              avatar: _isLocatingGps
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryGreen),
                                    )
                                  : const Icon(Icons.my_location, size: 15, color: WhatsAppTheme.primaryGreen),
                              label: const Text('Current GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _isLocatingGps ? null : () => _initAndAcquireGps(forceRequest: true),
                            ),
                            const SizedBox(width: 6),

                            // Real Saved Locations from Database
                            ..._savedLocations.map((loc) {
                              final label = loc['label']?.toString() ?? 'Place';
                              final lat = (loc['latitude'] as num?)?.toDouble() ?? 0.0;
                              final lng = (loc['longitude'] as num?)?.toDouble() ?? 0.0;
                              final name = loc['name']?.toString() ?? label;
                              final addr = loc['address']?.toString() ?? '';
                              final id = loc['id']?.toString() ?? '';

                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  avatar: Icon(_iconForLabel(label), size: 15, color: WhatsAppTheme.primaryGreen),
                                  label: Text(label, style: const TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    setState(() {
                                      _lat = lat;
                                      _lng = lng;
                                      _placeName = name;
                                      _address = addr;
                                    });
                                  },
                                ),
                              );
                            }),

                            // Bookmark / Save Location button
                            ActionChip(
                              avatar: const Icon(Icons.bookmark_add_outlined, size: 15, color: Colors.blue),
                              label: const Text('Save to DB', style: TextStyle(fontSize: 12, color: Colors.blue)),
                              onPressed: _openSaveLocationDialog,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Location Card Details
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: WhatsAppTheme.primaryGreen.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_pin, color: WhatsAppTheme.primaryGreen, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _placeName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _address.isNotEmpty ? _address : '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Action Buttons: Share Live Location vs Share Static Pin
                      Row(
                        children: [
                          // Live Location Option
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                side: const BorderSide(color: WhatsAppTheme.primaryGreen, width: 1.5),
                              ),
                              onPressed: _showLiveLocationDurationSheet,
                              icon: const Icon(Icons.sensors_rounded, color: WhatsAppTheme.primaryGreen, size: 18),
                              label: const Text(
                                'Live Location',
                                style: TextStyle(color: WhatsAppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Send Static Pin Button
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WhatsAppTheme.primaryGreen,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                Navigator.pop(
                                  context,
                                  LocationResult(
                                    latitude: _lat,
                                    longitude: _lng,
                                    name: _placeName,
                                    address: _address,
                                    isLive: false,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              label: const Text(
                                'Share Location',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
