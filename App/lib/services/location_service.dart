import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class DeviceLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final int? timestamp;
  final bool isGps;

  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0.0,
    this.altitude,
    this.speed,
    this.timestamp,
    this.isGps = true,
  });
}

class LocationService {
  static const MethodChannel _channel = MethodChannel('com.zelon.messenger/location');

  /// Check whether location permission is granted
  static Future<bool> hasPermission() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<String>('checkPermission');
      return res == 'granted';
    } catch (_) {
      return false;
    }
  }

  /// Explicitly trigger the Android runtime permission dialog
  static Future<bool> requestPermission() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<String>('requestPermission');
      return res == 'granted';
    } catch (_) {
      return false;
    }
  }

  /// Check if GPS or Network location providers are enabled
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isLocationEnabled');
      return res ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Open device Location Source settings screen
  static Future<void> openSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openLocationSettings');
    } catch (_) {}
  }

  /// Fetch device GPS location with high accuracy
  static Future<DeviceLocation?> getCurrentLocation({bool requestIfDenied = true}) async {
    if (kIsWeb) {
      return _fetchIpFallbackLocation();
    }

    try {
      // 1. Check & request permission if needed
      bool permitted = await hasPermission();
      if (!permitted && requestIfDenied) {
        permitted = await requestPermission();
      }
      if (!permitted) {
        return null;
      }

      // 2. Query native Android LocationManager
      final map = await _channel.invokeMapMethod<String, dynamic>('getCurrentLocation');
      if (map != null && map['latitude'] != null && map['longitude'] != null) {
        final lat = (map['latitude'] as num).toDouble();
        final lng = (map['longitude'] as num).toDouble();
        final acc = (map['accuracy'] as num?)?.toDouble() ?? 10.0;
        final alt = (map['altitude'] as num?)?.toDouble();
        final spd = (map['speed'] as num?)?.toDouble();
        final time = (map['time'] as num?)?.toInt();

        return DeviceLocation(
          latitude: lat,
          longitude: lng,
          accuracy: acc,
          altitude: alt,
          speed: spd,
          timestamp: time,
          isGps: true,
        );
      }
    } catch (e) {
      debugPrint('[LocationService] Native GPS error: $e');
    }

    // 3. Fallback to IP geolocation if native GPS timed out or in emulator
    return _fetchIpFallbackLocation();
  }

  /// IP-based fallback when GPS hardware is unavailable or in emulator
  static Future<DeviceLocation?> _fetchIpFallbackLocation() async {
    try {
      final url = Uri.parse('https://ipapi.co/json/');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final lat = (d['latitude'] as num?)?.toDouble();
        final lng = (d['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          return DeviceLocation(
            latitude: lat,
            longitude: lng,
            accuracy: 1000.0,
            isGps: false,
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
