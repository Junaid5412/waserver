import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatDesignService extends ChangeNotifier {
  static const String _prefWallpaperKey = 'zelon_chat_wallpaper';
  static const String _prefBubbleStyleKey = 'zelon_chat_bubble_style';
  static const String _prefFontSizeKey = 'zelon_chat_font_size';

  String _wallpaper = 'default';
  String _bubbleStyle = 'modern_rounded';
  String _fontSize = 'normal';

  String get wallpaper => _wallpaper;
  String get bubbleStyle => _bubbleStyle;
  String get fontSize => _fontSize;

  double get fontSizeValue {
    switch (_fontSize) {
      case 'compact':
        return 13.5;
      case 'comfortable':
        return 16.5;
      default:
        return 15.0;
    }
  }

  Color get wallpaperColor {
    switch (_wallpaper) {
      case 'dark_slate':
        return const Color(0xFF1E272C);
      case 'mint_emerald':
        return const Color(0xFF0F382C);
      case 'midnight_navy':
        return const Color(0xFF0D1B2A);
      case 'clean_charcoal':
        return const Color(0xFF18191A);
      default:
        return Colors.transparent;
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _wallpaper = prefs.getString(_prefWallpaperKey) ?? 'default';
    _bubbleStyle = prefs.getString(_prefBubbleStyleKey) ?? 'modern_rounded';
    _fontSize = prefs.getString(_prefFontSizeKey) ?? 'normal';
    notifyListeners();
  }

  Future<void> setWallpaper(String val) async {
    _wallpaper = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefWallpaperKey, val);
    notifyListeners();
  }

  Future<void> setBubbleStyle(String val) async {
    _bubbleStyle = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBubbleStyleKey, val);
    notifyListeners();
  }

  Future<void> setFontSize(String val) async {
    _fontSize = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefFontSizeKey, val);
    notifyListeners();
  }
}
