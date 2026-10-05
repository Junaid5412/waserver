import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/theme.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String name;
  final String address;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.address,
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
    _reverseGeocode(_lat, _lng);
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
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

    final centerLon = _tile2lon(centerTileX, _zoom);
    final centerLat = _tile2lat(centerTileY, _zoom);
    final nextLon = _tile2lon(centerTileX + 1, _zoom);
    final nextLat = _tile2lat(centerTileY + 1, _zoom);

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

        // Google English raster tile layer with OpenStreetMap fallback
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
          IconButton(
            icon: const Icon(Icons.my_location_rounded, color: Colors.white),
            tooltip: 'Reset to default location',
            onPressed: () {
              setState(() {
                _lat = 24.8607;
                _lng = 67.0011;
                _zoom = 15;
              });
              _reverseGeocode(_lat, _lng);
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            children: [
              // 1. Interactive Tile Map
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
                    const SizedBox(height: 48), // offsets pin point to true center
                  ],
                ),
              ),

              // 3. Zoom Controls (+ / -)
              Positioned(
                right: 16,
                top: 80,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'zoom_in',
                      backgroundColor: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                      foregroundColor: WhatsAppTheme.primaryGreen,
                      onPressed: () {
                        if (_zoom < 18) setState(() => _zoom++);
                      },
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 8),
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

              // 4. English Place Search Bar
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

              // 5. Bottom Location Info & Send Sheet
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  decoration: BoxDecoration(
                    color: isDark ? WhatsAppTheme.surfaceDark : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -3))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Quick Preset Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.my_location, size: 15, color: WhatsAppTheme.primaryGreen),
                              label: const Text('Current', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _lat = 24.8607;
                                  _lng = 67.0011;
                                });
                                _reverseGeocode(_lat, _lng);
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: const Icon(Icons.business_rounded, size: 15, color: WhatsAppTheme.primaryGreen),
                              label: const Text('Office', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _lat = 24.8615;
                                  _lng = 67.0099;
                                });
                                _reverseGeocode(_lat, _lng);
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: const Icon(Icons.home_rounded, size: 15, color: WhatsAppTheme.primaryGreen),
                              label: const Text('Home', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _lat = 24.8710;
                                  _lng = 67.0200;
                                });
                                _reverseGeocode(_lat, _lng);
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              avatar: const Icon(Icons.flight_rounded, size: 15, color: WhatsAppTheme.primaryGreen),
                              label: const Text('Airport', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _lat = 24.9065;
                                  _lng = 67.1608;
                                });
                                _reverseGeocode(_lat, _lng);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

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
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _address.isNotEmpty ? _address : '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WhatsAppTheme.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(
                            context,
                            LocationResult(
                              latitude: _lat,
                              longitude: _lng,
                              name: _placeName,
                              address: _address,
                            ),
                          );
                        },
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        label: const Text(
                          'Share Selected Location',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
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
